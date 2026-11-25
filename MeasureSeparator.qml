// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import MuseScore 3.0
import Muse.Ui

MuseScore {
    id: root
    title: "Measure Separator"
    description: "Separates measures with native horizontal frames."
    version: "0.1.4"
    thumbnailName: "MeasureSeparator.png"
    pluginType: "action"
    requiresScore: true

    readonly property bool japanese: /^ja(?:_|-|$)/i.test(Qt.locale().name)
    readonly property bool supported: mscoreMajorVersion === 4 && mscoreMinorVersion === 7 && mscoreUpdateVersion === 7
    readonly property string legacyMarkerPrefix: "org.measureseparator.hbox.v1.20261125:"
    readonly property string markerPrefix: "\u2063\u2062\u2064\u2063\u2064\u2062"
    readonly property string markerDigits: "\u200b\u200c\u2060\u2063"
    readonly property string base64Digits: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    onRun: {
        // Keep the notation page active in MuseScore's action context.
        // The managed legacy plugin dialog can block insert-hbox in Studio 4.7.7.
        panelLoader.active = true
        panelLoader.item.openFor(curScore)
    }

    function ui(ja, en) { return japanese ? ja : en }

    function measuresOf(score) {
        const measures = []
        for (let measure = score.firstMeasure; measure; measure = measure.nextMeasure)
            measures.push(measure)
        return measures
    }

    function endTick(measure) { return measure.tick.plus(measure.ticks).ticks }

    function same(a, b) { return a && b && a.is(b) }

    function captureSelection(score) {
        const selection = score.selection
        if (selection.isRange) {
            return {
                first: selection.startSegment.tick,
                end: selection.endSegment ? selection.endSegment.tick : endTick(score.lastMeasure),
                firstStaff: selection.startStaff,
                endStaff: selection.endStaff
            }
        }
        return { elements: Array.from(selection.elements) }
    }

    function restoreSelection(score, saved) {
        const selection = score.selection
        selection.clear()
        if (saved.first !== undefined)
            selection.selectRange(saved.first, saved.end, saved.firstStaff, saved.endStaff)
        else
            saved.elements.forEach((element, index) => selection.select(element, index > 0))
    }

    function rangeOf(measures, selected, saved) {
        if (!selected)
            return { first: 0, end: measures.length }
        if (saved.first === undefined)
            throw new Error(ui("楽譜上で小節範囲を選択してから開いてください。",
                               "Select a measure range in the score before opening the plugin."))
        const first = measures.findIndex(m => endTick(m) > saved.first)
        const end = measures.findIndex(m => m.tick.ticks >= saved.end)
        if (first < 0 || (end >= 0 && end <= first))
            throw new Error(ui("選択範囲に小節がありません。", "The selection contains no measures."))
        return { first: first, end: end < 0 ? measures.length : end }
    }

    // A frame is owned only while its sole child is our invisible marker.
    // Records store the original and last applied display state, keyed by native measure EID.
    function encodeState(records) {
        // Use zero-width format characters so showing invisible elements reveals no text.
        const payload = Qt.btoa(JSON.stringify(records)).replace(/=+$/, "")
        let text = markerPrefix
        for (const character of payload) {
            const digit = base64Digits.indexOf(character)
            text += markerDigits[digit >> 4] + markerDigits[(digit >> 2) & 3] + markerDigits[digit & 3]
        }
        return text
    }

    function isMarkerText(text) {
        return text.startsWith(markerPrefix) || text.startsWith(legacyMarkerPrefix)
    }

    function decodeState(text) {
        if (text.startsWith(legacyMarkerPrefix))
            return JSON.parse(Qt.atob(text.slice(legacyMarkerPrefix.length)))

        const payload = text.slice(markerPrefix.length)
        if (payload.length % 3 !== 0)
            throw new Error(ui("フレームの復元情報が破損しています。", "A frame has damaged restoration data."))
        let base64 = ""
        for (let offset = 0; offset < payload.length; offset += 3) {
            const first = markerDigits.indexOf(payload[offset])
            const second = markerDigits.indexOf(payload[offset + 1])
            const third = markerDigits.indexOf(payload[offset + 2])
            if (first < 0 || second < 0 || third < 0)
                throw new Error(ui("フレームの復元情報が破損しています。", "A frame has damaged restoration data."))
            base64 += base64Digits[(first << 4) | (second << 2) | third]
        }
        return JSON.parse(Qt.atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")))
    }

    function ownership(frame) {
        if (!frame || frame.type !== Element.HBOX || frame.elements.length !== 1)
            return null
        const marker = frame.elements[0]
        if (marker.type !== Element.TEXT || marker.visible || !isMarkerText(marker.text))
            return null
        const state = decodeState(marker.text)
        if (!Array.isArray(state) || state.some(record =>
            !Array.isArray(record) || record.length !== 4 || typeof record[0] !== "string"
                || !Number.isInteger(record[1]) || record[1] < -1
                || !Number.isInteger(record[2]) || !Number.isInteger(record[3])))
            throw new Error(ui("フレームの復元情報が破損しています。", "A frame has damaged restoration data."))
        return { frame: frame, marker: marker, state: state }
    }

    function ownsMarker(frame) {
        return frame.type === Element.HBOX && Array.from(frame.elements).some(item =>
            item.type === Element.TEXT && isMarkerText(item.text))
    }

    function framesOf(score) {
        let first = score.firstMeasure
        while (first.prev)
            first = first.prev
        const frames = []
        for (let item = first; item; item = item.next) {
            const owned = ownership(item)
            if (owned)
                frames.push(owned)
            else if (ownsMarker(item))
                throw new Error(ui("追加フレームに編集があるため処理を中止しました。",
                                   "A separator frame was edited. The operation was stopped."))
        }
        return frames
    }

    function hasBreak(measure) {
        return Array.from(measure.elements).some(item => item.type === Element.LAYOUT_BREAK
            && item.layoutBreakType !== LayoutBreak.NOBREAK)
    }

    function chordRestAnchor(measure, tracks) {
        for (const segment of measure.segments) {
            if (segment.segmentType !== Segment.ChordRest)
                continue
            for (let track = 0; track < tracks; ++track) {
                const item = segment.elementAt(track)
                if (item && item.type === Element.CHORD && item.notes.length)
                    return item.notes[0]
                if (item && item.type === Element.REST)
                    return item
            }
        }
        return null
    }

    function repeatGroupBoundaries(measures, tracks) {
        const blocked = new Set()
        for (let index = 0; index < measures.length; ++index) {
            for (const segment of measures[index].segments) {
                if (segment.segmentType !== Segment.ChordRest)
                    continue
                for (let track = 0; track < tracks; ++track) {
                    const item = segment.elementAt(track)
                    if (!item || item.type !== Element.MEASURE_REPEAT || item.subtype < 2)
                        continue
                    // MuseScore anchors the repeat sign in the middle of its measure group.
                    const count = item.subtype
                    const first = index - Math.floor((count - 1) / 2)
                    for (let boundary = first + 1; boundary < first + count; ++boundary)
                        blocked.add(boundary)
                }
            }
        }
        return blocked
    }

    function measureBaseCount(score) {
        let first = score.firstMeasure
        while (first.prev)
            first = first.prev
        let count = 0
        for (let item = first; item; item = item.next)
            ++count
        return count
    }

    function setFrame(frame, widthSp) {
        if (Math.abs(frame.boxWidth - widthSp) > 0.001)
            frame.boxWidth = widthSp
        if (frame.topGap !== 0) frame.topGap = 0
        if (frame.bottomGap !== 0) frame.bottomGap = 0
        if (frame.createSystemHeader) frame.createSystemHeader = false
    }

    function insertFrame(score, measure, anchor, widthSp, previousCount) {
        if (!score.selection.select(anchor))
            throw new Error(ui("挿入位置を選択できませんでした。", "Could not select the insertion point."))
        cmd("insert-hbox")
        const frame = measure.prev
        if (!frame || frame.type !== Element.HBOX || frame.elements.length !== 0) {
            if (measureBaseCount(score) === previousCount)
                return false
            throw new Error(ui("水平フレームが指定位置以外に挿入されたため、変更を取り消しました。",
                               "A frame was inserted at an unexpected position. Changes were rolled back."))
        }
        setFrame(frame, widthSp)
        const marker = newElement(Element.TEXT)
        marker.text = encodeState([])
        marker.visible = false
        frame.add(marker)
        if (!ownership(frame))
            throw new Error(ui("フレームを識別できませんでした。", "Could not identify the new frame."))
        return true
    }

    function removeFrame(frame) {
        const right = frame.next
        const left = frame.prev
        removeElement(frame)
        if ((right && same(right.prev, frame)) || (left && same(left.next, frame)))
            throw new Error(ui("水平フレームを削除できませんでした。", "Could not delete the horizontal frame."))
    }

    function layout(score) {
        score.doLayout(score.firstMeasure.tick, score.lastMeasure.tick.plus(score.lastMeasure.ticks))
    }

    function measureIds(measures) {
        const ids = new Map()
        for (const measure of measures) {
            const eid = measure.eid
            if (!eid || eid === "//////////P_//////////P")
                continue
            ids.set(eid, ids.has(eid) ? null : measure)
        }
        return ids
    }

    function endBar(measure, track) {
        const segment = measure.lastSegment
        // Courtesy key/time signatures may follow the end barline.
        if (segment && segment.segmentType === Segment.EndBarLine)
            return segment.elementAt(track)
        for (const candidate of measure.segments) {
            if (candidate.segmentType === Segment.EndBarLine)
                return candidate.elementAt(track)
        }
        return null
    }

    function normalBar(item) {
        return item && item.type === Element.BAR_LINE && item.barlineType === BarLineType.NORMAL
    }

    function restoreRecord(record, ids, totalTracks) {
        const measure = ids.get(record[0])
        if (!measure)
            return false
        if (record[1] === -1) {
            if (measure.measureNumberMode === record[3])
                measure.measureNumberMode = record[2]
        } else if (record[1] < totalTracks) {
            const bar = endBar(measure, record[1])
            if (normalBar(bar) && Number(bar.visible) === record[3])
                bar.visible = Boolean(record[2])
        }
        return true
    }

    function applyDisplay(score, measures, range, options, ids, records, canStore) {
        let skipped = 0
        if (!options.hideBars && options.numberMode === 0)
            return skipped
        for (let index = range.first; index < range.end; ++index) {
            const measure = measures[index]
            if (!canStore || !same(ids.get(measure.eid), measure)) {
                ++skipped
                continue
            }
            if (options.numberMode !== 0 && measure.measureNumberMode !== options.numberMode) {
                records.push([measure.eid, -1, measure.measureNumberMode, options.numberMode])
                measure.measureNumberMode = options.numberMode
            }
            if (!options.hideBars || index === measures.length - 1)
                continue
            for (let track = 0; track < score.ntracks; track += 4) {
                const bar = endBar(measure, track)
                if (normalBar(bar) && bar.visible) {
                    records.push([measure.eid, track, 1, 0])
                    bar.visible = false
                }
            }
        }
        return skipped
    }

    function visibleMeasures(score) {
        const ids = new Map()
        for (let measure = score.firstMeasureMM; measure; measure = measure.nextMeasureMM)
            ids.set(measure.tick.ticks, measure)
        return ids
    }

    function trimSystemEdges(score, rangeStart, rangeEnd) {
        let count = 0
        // Removing an edge frame can shift the next automatic break.
        // Each pass removes frames monotonically. User frames stay untouched.
        for (;;) {
            const edges = []
            for (const system of score.systems) {
                const first = system.firstMeasure
                const last = system.lastMeasure
                if (!first || !last)
                    continue
                for (const candidate of system.measures) {
                    const tick = candidate.tick.ticks
                    if (candidate.type === Element.HBOX && tick > rangeStart && tick < rangeEnd
                            && (tick <= first.tick.ticks || tick >= endTick(last)) && ownership(candidate))
                        edges.push(candidate)
                }
            }
            if (edges.length === 0)
                return count
            edges.forEach(removeFrame)
            count += edges.length
            layout(score)
        }
    }

    function editScore(score, options, removing) {
        const measures = measuresOf(score)
        if (!measures.length)
            throw new Error(ui("処理できる小節がありません。", "There are no measures to process."))
        // HBox commands can clone frames to linked parts. Keep the ownership scope unambiguous.
        if (score.excerpts.length !== 0)
            throw new Error(ui("リンクされたパート譜があるスコアには、独立した譜面ファイルをご使用ください。",
                               "Use a standalone score file when the project has linked parts."))
        const saved = captureSelection(score)
        const range = rangeOf(measures, !removing && options.selected, saved)
        const ids = measureIds(measures)
        const initial = framesOf(score)
        const records = []
        const affected = new Set(measures.slice(range.first, range.end).map(measure => measure.eid))
        let skipped = 0
        let edges = 0
        let restored = 0
        let rejected = 0
        let firstRejected = 0
        score.startCmd(removing ? "Remove Measure Separators" : "Apply Measure Separators")
        try {
            for (const entry of initial) {
                for (const record of entry.state) {
                    if (removing || affected.has(record[0])) {
                        if (restoreRecord(record, ids, score.ntracks)) ++restored
                        else ++skipped
                    } else {
                        records.push(record)
                    }
                }
            }
            if (removing) {
                initial.forEach(entry => removeFrame(entry.frame))
            } else {
                const visible = visibleMeasures(score)
                const repeatBoundaries = repeatGroupBoundaries(measures, score.ntracks)
                const keep = new Set()
                let itemCount = measureBaseCount(score)
                for (let index = range.first + 1; index < range.end; ++index) {
                    const left = measures[index - 1]
                    const right = measures[index]
                    if ((index - range.first) % options.interval !== 0)
                        continue
                    const owned = ownership(right.prev)
                    if (repeatBoundaries.has(index) || hasBreak(left)
                            || !same(visible.get(right.tick.ticks), right)) {
                        ++skipped
                        continue
                    }
                    if (owned) {
                        setFrame(owned.frame, options.width)
                        keep.add(right.tick.ticks)
                    } else if (same(left, right.prev)) {
                        const anchor = chordRestAnchor(right, score.ntracks)
                        if (!anchor) {
                            ++skipped
                        } else if (insertFrame(score, right, anchor, options.width, itemCount)) {
                            ++itemCount
                            keep.add(right.tick.ticks)
                        } else {
                            if (!firstRejected)
                                firstRejected = index + 1
                            ++rejected
                        }
                    }
                }
                if (!keep.size && rejected)
                    throw new Error(ui("MuseScoreが挿入を受け付けませんでした。最初の拒否位置は先頭から%1番目の小節の手前です。",
                                       "MuseScore refused the insertions. The first refusal was before measure position %1.")
                                    .arg(firstRejected))
                for (let index = range.first + 1; index < range.end; ++index) {
                    const right = measures[index]
                    if (!keep.has(right.tick.ticks) && ownership(right.prev))
                        removeFrame(right.prev)
                }
                layout(score)
                edges = trimSystemEdges(score, measures[range.first].tick.ticks, endTick(measures[range.end - 1]))
                let remaining = framesOf(score)
                skipped += applyDisplay(score, measures, range, options, ids, records, remaining.length > 0)
                layout(score)
                edges += trimSystemEdges(score, measures[range.first].tick.ticks, endTick(measures[range.end - 1]))
                remaining = framesOf(score)
                // Keep the ledger on one surviving frame so it travels with the score.
                for (let index = 0; index < remaining.length; ++index) {
                    const value = encodeState(index === 0 ? records : [])
                    if (remaining[index].marker.text !== value)
                        remaining[index].marker.text = value
                }
                if (records.length && !remaining.length)
                    throw new Error(ui("復元情報を保存できるフレームがありません。",
                                       "No separator frame remains to hold restoration data."))
            }
            layout(score)
        } catch (error) {
            score.endCmd(true)
            restoreSelection(score, saved)
            throw error
        }
        score.endCmd()
        restoreSelection(score, saved)
        return { frames: framesOf(score).length, skipped: skipped, edges: edges, restored: restored, rejected: rejected }
    }

    Loader {
        id: panelLoader
        active: false
        sourceComponent: Component {
            Window {
                id: panel
                title: root.title + " " + root.version
                width: 650
                height: 510
                minimumWidth: 520
                minimumHeight: 450
                flags: Qt.Dialog | Qt.WindowCloseButtonHint
                modality: Qt.NonModal
                color: panelPalette.window
                property var openedScore: null
                property string status: ""
                property bool busy: false

                SystemPalette { id: panelPalette }
                Settings { id: preferences; category: "MeasureSeparator" }

                onClosing: Qt.callLater(function() { panelLoader.active = false })

                function openFor(score) {
                    openedScore = score
                    interval.value = Number(preferences.value("interval", 1)) || 1
                    gap.value = Number(preferences.value("gapSteps", 6)) || 6
                    barlines.currentIndex = Number(preferences.value("barlines", 0)) === 1 ? 1 : 0
                    let mode = Number(preferences.value("numbers", 0))
                    numbers.currentIndex = mode === 1 || mode === 2 ? mode : 0
                    scope.currentIndex = score && score.selection.isRange ? 1 : 0
                    show()
                    requestActivate()
                }

                function savePreferences() {
                    preferences.setValue("interval", interval.value)
                    preferences.setValue("gapSteps", gap.value)
                    preferences.setValue("barlines", barlines.currentIndex)
                    preferences.setValue("numbers", numbers.currentIndex)
                }

                function runEdit(removing) {
                    busy = true
                    try {
                        const current = root.curScore
                        if (!root.same(current, openedScore)) {
                            status = root.ui("プラグインを開いたときの楽譜に戻ってください。",
                                        "Return to the score that was open when you started the plugin.")
                            return
                        }
                        const result = root.editScore(current, {
                            selected: scope.currentIndex === 1, interval: interval.value, width: gap.value / 2,
                            hideBars: barlines.currentIndex === 1, numberMode: numbers.currentIndex
                        }, removing)
                        savePreferences()
                        status = removing
                            ? root.ui("分割を解除しました。復元した表示設定 ", "Separators removed. Display settings restored ") + result.restored
                            : root.ui("追加フレームの合計 ", "Total separator frames ") + result.frames
                                + root.ui(" ／ 行端で省略 ", " / Omitted at system edges ") + result.edges
                        if (result.skipped)
                            status += root.ui(" ／ 条件により未処理 ", " / Skipped ") + result.skipped
                        if (result.rejected)
                            status += root.ui(" ／ MuseScoreが挿入を拒否 ", " / Insertions refused by MuseScore ") + result.rejected
                    } catch (error) {
                        status = error.message || String(error)
                    } finally {
                        busy = false
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 10

                    Label { text: "Measure Separator"; font.pixelSize: 24; font.bold: true }

                    Label {
                        Layout.fillWidth: true
                        visible: !root.supported
                        wrapMode: Text.WordWrap
                        text: root.ui("この版は MuseScore Studio 4.7.7 に対応しています。",
                                      "This release supports MuseScore Studio 4.7.7.")
                    }

                    GridLayout {
                        columns: 2
                        columnSpacing: 18
                        rowSpacing: 8
                        Layout.fillWidth: true

                        Label { text: root.ui("適用範囲", "Scope") }
                        ComboBox {
                            id: scope
                            Layout.fillWidth: true
                            model: [root.ui("楽譜全体", "Whole score"), root.ui("選択した小節範囲", "Selected measures")]
                        }

                        Label { text: root.ui("分割間隔（小節）", "Group size (measures)") }
                        SpinBox { id: interval; from: 1; to: 9999; value: 1; editable: true }

                        Label { text: root.ui("余白幅（sp）", "Gap width (sp)") }
                        RowLayout {
                            Layout.fillWidth: true
                            Slider {
                                Layout.fillWidth: true
                                from: 1; to: 20; stepSize: 1; snapMode: Slider.SnapAlways
                                value: gap.value
                                onMoved: gap.value = Math.round(value)
                                Accessible.name: root.ui("余白幅スライダー", "Gap width slider")
                            }
                            SpinBox {
                                id: gap
                                from: 1; to: 20; value: 6; editable: true
                                validator: DoubleValidator {
                                    bottom: 0.5; top: 10; decimals: 1; notation: DoubleValidator.StandardNotation
                                }
                                textFromValue: function(value, locale) { return Number(value / 2).toLocaleString(locale, "f", 1) }
                                valueFromText: function(value, locale) { return Math.round(Number.fromLocaleString(locale, value) * 2) }
                                Accessible.name: root.ui("余白幅の入力", "Gap width input")
                            }
                        }

                        Label { text: root.ui("通常の小節線", "Ordinary barlines") }
                        ComboBox {
                            id: barlines
                            Layout.fillWidth: true
                            model: [root.ui("元の表示設定に従う", "Use original visibility"),
                                    root.ui("非表示", "Hide")]
                        }

                        Label { text: root.ui("小節番号", "Measure numbers") }
                        ComboBox {
                            id: numbers
                            Layout.fillWidth: true
                            model: [root.ui("楽譜の表示設定に従う", "Use score settings"),
                                    root.ui("すべての小節に表示", "Show all"), root.ui("非表示", "Hide")]
                        }
                    }

                    Label { text: root.ui("プレビュー（模式図）", "Layout preview (schematic)") }
                    Canvas {
                        id: preview
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
                        readonly property int groupSize: interval.value
                        readonly property int spaceSteps: gap.value
                        readonly property bool showBars: barlines.currentIndex === 0
                        readonly property int numberMode: numbers.currentIndex
                        onGroupSizeChanged: requestPaint()
                        onSpaceStepsChanged: requestPaint()
                        onShowBarsChanged: requestPaint()
                        onNumberModeChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: {
                            const context = getContext("2d")
                            context.reset()
                            context.fillStyle = "#f9fafb"
                            context.fillRect(0, 0, width, height)
                            const count = 6
                            const empty = 2.5 * spaceSteps
                            const groupGaps = Math.floor((count - 1) / groupSize)
                            const measureWidth = (width - 32 - groupGaps * empty) / count
                            let x = 16
                            for (let index = 0; index < count; ++index) {
                                context.strokeStyle = "#465260"
                                context.beginPath()
                                for (let line = 0; line < 5; ++line) {
                                    context.moveTo(x, 22 + line * 6)
                                    context.lineTo(x + measureWidth, 22 + line * 6)
                                }
                                if (showBars || index === count - 1) {
                                    context.moveTo(x + measureWidth, 22)
                                    context.lineTo(x + measureWidth, 46)
                                }
                                context.stroke()
                                context.fillStyle = "#293947"
                                context.beginPath()
                                context.ellipse(x + measureWidth / 2 - 5, 35 - (index % 3) * 3, 10, 7)
                                context.fill()
                                if (numberMode === 1 || (numberMode === 0 && index === 0))
                                    context.fillText(String(index + 1), x + 3, 16)
                                x += measureWidth + ((index + 1) % groupSize === 0 ? empty : 0)
                            }
                        }
                    }

                    Label { Layout.fillWidth: true; Layout.fillHeight: true; wrapMode: Text.WordWrap; text: panel.status }

                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            text: root.ui("適用", "Apply")
                            enabled: root.supported && !panel.busy
                            highlighted: true
                            onClicked: panel.runEdit(false)
                        }
                        Button {
                            text: root.ui("分割解除", "Remove separators")
                            enabled: root.supported && !panel.busy
                            onClicked: panel.runEdit(true)
                        }
                        Button {
                            text: root.ui("初期設定に戻す", "Reset settings")
                            onClicked: {
                                interval.value = 1
                                gap.value = 6
                                barlines.currentIndex = 0
                                numbers.currentIndex = 0
                                panel.savePreferences()
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Button { text: root.ui("閉じる", "Close"); onClicked: panel.close() }
                    }
                }
            }
        }
    }
}
