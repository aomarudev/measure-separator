# Measure Separator 要件定義書

## 目的

小節間の五線のない空白により譜面を視覚的に分節し、初見演奏と練習時の読譜を補助します。実装はMuseScore標準の水平フレーム（HBox）を使い、音符、休符、小節の追加や本体改造を伴いません。

Stenberg & Cross（2019）および Duncan, Ness & Cross（2026）は、音楽的なまとまりを余白で区切った譜面の初見演奏を研究しています。本プロジェクトが用いる固定小節間隔の効果は別途評価します。

- [Stenberg & Cross（2019）](https://doi.org/10.1038/s41598-019-41445-1)
- [Duncan, Ness & Cross（2026）](https://doi.org/10.1177/10298649261419805)

## 機能要件

| ID | 要件 | 0.1.0での実装範囲 |
|---|---|---|
| FR-01 | HBoxで五線を物理的に分断し、小節番号・拍数・再生時間を維持 | 五線を全段で分割。既定は1小節 |
| FR-02 | 1、2、3、4および任意小節数で分割 | 1～9,999。弱起を1小節に数え、範囲先頭から数える |
| FR-03 | 0.5～10.0 sp、0.5 sp刻み。既定3.0 sp | スライダーと数値入力 |
| FR-04 | 全譜面または選択した小節範囲 | 選択の開始・終了に接する小節を対象化し、範囲内の境界へ適用 |
| FR-05 | 通常の小節線の表示制御、特殊線・反復再生の維持 | 通常の小節末の線のみ。既存設定を維持するモードが既定 |
| FR-06 | 標準、全小節で表示、非表示。番号付けは維持 | 元の個別設定、強制表示、強制非表示 |
| FR-07 | 自動改行・改ページに対応し、行端の余白を除く | 明示的な改行を避け、適用時の自動組段で行端の追加枠を除去 |
| FR-08 | 音高、音価、リズム、調号、拍子記号、臨時記号、タイ、スラー、アーティキュレーション、強弱、テンポ、反復、D.C.・D.S.・Coda、歌詞、コード、リハーサルマーク、連符、装飾音符を維持 | 楽譜要素の操作はフレーム、表示属性に限定。特殊記譜の検証は[T08–T13ほか](TEST_RESULTS.md) |
| FR-09 | 単旋律、管楽器パート、複数声部、ピアノ、アンサンブル、管弦楽 | 同一システムの全五線で位置を共有。リンク済みパートがある場合は停止 |
| FR-10 | 再実行時の重複防止、既存フレームの保護、設定変更 | マーカー付きフレームを更新し、範囲内で不要になったものを除去 |
| FR-11 | Undo、一括解除、保存後の解除 | 編集をUndoトランザクション化。復元識別子はスコア内に保存 |
| FR-12 | 間隔、幅、小節線、小節番号の設定を保持 | MuseScoreのSettingsを使用 |
| FR-13 | MSCZ・MSCX保存、再読み込み、PDF・印刷、再生 | MuseScore標準のデータ構造と出力機能を使用。テストの範囲は別紙 |
| FR-14 | Accidental Colorと順序を問わず併用 | 独立配布。同じテスト譜で両順序を確認 |

## UI・非機能要件

日本語・英語の画面に適用範囲、間隔、余白幅、小節線、小節番号、模式プレビューを表示します。適用、分割解除、設定初期化、閉じるを提供します。QML単体で動作し、通信や外部依存関係を要しません。失敗が発生した編集はUndoのロールバックを使って戻します。大規模スコアの処理時間の基準値は未設定です。

## 実装に使用したAPI

| 目的 | v4.7.7のAPIまたは実装 |
|---|---|
| 小節とフレームの走査 | `firstMeasure`、`nextMeasure`、`prev`、`next` |
| 選択と挿入 | 選択範囲は`Selection.startSegment/endSegment`。楽譜の音符・休符を選択し `cmd("insert-hbox")` |
| 幅と削除 | `boxWidth`、`topGap`、`bottomGap`、`createSystemHeader`、`removeElement` |
| 永続識別 | HBoxの子となる不可視Textと小節EID。プラグイン固有の識別記号で所有判定 |
| 表示 | 通常のBarLineの `visible` と小節の `measureNumberMode` |
| Undoと描画 | `startCmd`、`endCmd(rollback)`、`doLayout`、`score.systems` |
| 設定 | `Muse.Ui.Settings` |

- [v4.7.7 QMLプラグインAPI](https://github.com/musescore/MuseScore/blob/v4.7.7/src/engraving/api/v1/qmlpluginapi.cpp)
- [v4.7.7 Score・Selection API](https://github.com/musescore/MuseScore/tree/v4.7.7/src/engraving/api/v1)
- [v4.7.7 HBoxとフレームの処理](https://github.com/musescore/MuseScore/blob/v4.7.7/src/engraving/dom/box.cpp)
- [v4.7.7 スコア書き出し実装](https://github.com/musescore/MuseScore/blob/v4.7.7/src/engraving/rw/write/twrite.cpp)

## 開発と検証

1. 単旋律の挿入、幅、全譜面、Undo、重複防止、PDFを確認します。
2. GUI、間隔、選択範囲、表示設定、解除、永続化、複数五線を追加します。
3. 特殊記譜、改行、既存フレーム、Accidental Colorを受入テストで検証し、配布資料を整備します。
4. 通常譜、分割、色分け、分割と色分けの併用を、難易度をそろえた別譜例で比較します。音程誤り率、リズム誤り率、見失い、演奏中断、初見テンポ、主観的な読みやすさ、NASA-TLX等の認知負荷を記録します。
