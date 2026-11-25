# Windows 11 インストール手順

1. MuseScore Studioの **ヘルプ → MuseScore Studioについて** で、バージョンが **4.7.7** であることを確認します。
2. ZIPを展開し、`MeasureSeparator.qml` と `MeasureSeparator.png` を同じプラグインフォルダーにコピーします。既定では `%USERPROFILE%\Documents\MuseScore4\Plugins\` です。実際の場所はMuseScoreの **環境設定 → フォルダー** で確認できます。
3. MuseScoreの **ホーム → プラグイン** または **プラグイン → プラグインの管理** を開き、**Measure Separator** を有効にします。表示されない場合は、ファイル名と配置場所を確認してMuseScoreを再起動します。
4. 最初は `TestScores/FourBars.mscz` を開き、**プラグイン → Measure Separator → 適用** を実行します。既定では4小節の境界3か所に分割が入り、**分割解除** で元の表示に戻ります。

旧版から更新するときは、`MeasureSeparator.qml` を差し替えた後にMuseScoreを終了して再起動します。適用済みの楽譜に識別文字列が見える場合は、同じ設定で **適用** を押し、楽譜を保存します。

PDF出力と印刷はMuseScoreの標準機能を使用します。保存した分割譜を人に渡す場合は、使用するMuseScoreの版も合わせて伝えてください。

[公式ハンドブックのプラグイン管理とインストール](https://handbook.musescore.org/customization/plugins)
