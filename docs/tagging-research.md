# タグ読み書き技術調査

## 結論

MVP では `ID3TagEditor` を第一候補として採用し、Liner 側には薄い `AudioTagStore` 境界を置く方針にします。

理由は、MVP の対象が MP3 / ID3v2 に限定されており、`ID3TagEditor` が Swift Package Manager で導入できる純 Swift ライブラリとして、ID3v2.2 / 2.3 / 2.4 の読み書き、macOS 対応、カバーアートを含む主要タグ編集に合っているためです。TagLib は成熟度と将来の FLAC / MP4 / Vorbis Comment 対応で魅力がありますが、初期段階では C++ ライブラリのビルド、配布、Swift 連携、ライセンス表記の負荷が大きいため、MVP の第一候補からは外します。

## MVP 方針

- 読み込みは ID3v2.3 / ID3v2.4 の両方を受け付ける。
- 書き込みは互換性を優先し、初期方針として ID3v2.3 を第一候補にする。
- 既存ファイルが ID3v2.4 の場合は、初期検証で `ID3TagEditor` の保存バージョン制御と保持挙動を確認する。
- テキストはアプリ内部で Swift `String` に正規化し、書き込み時の文字コードはライブラリの既定挙動を確認して固定する。
- カバーアートは ID3v2 の APIC frame として扱い、MVP では front cover 1 枚を基本にする。
- Liner の UI / 変更追跡モデルはライブラリ固有型を直接持たず、共通の `TrackMetadata` と `ArtworkMetadata` に変換する。
- 保存前プレビューとバックアップ方針を後続 issue で扱うため、タグ書き込み API は「読み込み」「差分作成」「書き込み」を分けて設計する。

## 比較

| 候補 | 採用判断 | 良い点 | 懸念 / 不採用理由 |
| --- | --- | --- | --- |
| `ID3TagEditor` | MVP 第一候補 | Swift Package Manager 対応。純 Swift。ID3v2.2 / 2.3 / 2.4 の読み書きに対応。MIT license。macOS を含む Apple platform で使える。 | MP3 / ID3 に特化しているため、FLAC / MP4 などの将来形式には別実装が必要。保存時に未知 frame をどこまで保持できるか、文字コードとバージョン変換挙動を fixture で確認する必要がある。 |
| TagLib 直接利用 | 将来候補 | 長く使われている C++ ライブラリ。ID3v1 / ID3v2、FLAC / Vorbis Comment、MP4 など幅広い形式に対応。Unicode と format-specific API もある。 | C++ のビルド、署名・notarization を含む配布、Swift からのラップ、MPL / LGPL の遵守確認が必要。MVP の MP3 限定スコープには初期負荷が大きい。 |
| `SwiftTagLib.cpp` | 将来候補 | TagLib を Swift C++ interop 経由で扱う Swift 向けラッパー。画像の読み書き例もある。 | 比較的新しい小規模ライブラリで、ABI 安定性を保証しない旨が明記されている。MVP の土台としては依存リスクが高い。 |
| AVFoundation | 読み取り補助候補 | Apple 標準 API。`AVMetadataItem` と ID3 metadata identifier でメタデータを読める。追加依存がない。 | タグエディタとしての細かな ID3v2 書き換え、未知 frame の保持、APIC の制御、ID3v2.3 / 2.4 の保存方針に向かない。MVP の主要書き込み手段にはしない。 |
| 自前実装 | 不採用 | 依存を最小化でき、Liner の要件に合わせて未知 frame 保持や安全書き込みを細かく制御できる。 | ID3v2.3 / 2.4 の frame size、unsynchronisation、文字コード、APIC、コメント、複数値、既存タグ保持などの実装・検証負荷が高い。MVP ではプロダクト価値に届くまでが遅くなる。 |

## ID3v2.3 / ID3v2.4 の注意点

ID3v2.4 は ID3v2.3 を置き換える改訂版として定義されていますが、実際の互換性では ID3v2.3 のほうが古いプレイヤーやツールで安定しやすい前提で扱います。MVP では読み取り互換を広く、書き込み形式を保守的にするのが安全です。

実装時に fixture で確認する項目:

- `TIT2`, `TPE1`, `TALB`, `TPE2`, `TRCK`, `TPOS`, `TCON`, `TYER` / `TDRC`, `COMM`, `APIC` の読み書き。
- ID3v2.3 と ID3v2.4 の既存ファイルを読み込み、保存後に主要 frame が失われないこと。
- UTF-8 / UTF-16 / ISO-8859-1 相当の文字列を含むタグで文字化けしないこと。
- 既存のカバーアートを読み込み、front cover として置き換えられること。
- Liner が編集対象にしない frame を保存時に破壊しない、または破壊する場合は仕様として明示できること。

## 初期実装メモ

最初のアプリ実装では、タグ処理を UI から直接呼ばず、次のような境界を置きます。

```swift
protocol AudioTagStore {
    func loadMetadata(from url: URL) throws -> TrackMetadata
    func writeMetadata(_ metadata: TrackMetadata, to url: URL) throws
}
```

`ID3TagEditorAudioTagStore` はこの protocol の具象実装として置き、将来 `TagLibAudioTagStore` を追加できるようにします。これにより、MVP では Swift 実装の軽さを取りつつ、FLAC 対応や ID3 の保持精度で限界が見えた時に置き換えやすくします。

## 参照

- ID3TagEditor: https://github.com/chicio/ID3TagEditor
- ID3TagEditor on Swift Package Index: https://swiftpackageindex.com/chicio/ID3TagEditor
- TagLib: https://taglib.org/
- TagLib API documentation: https://taglib.org/api/
- SwiftTagLib.cpp: https://github.com/Anywhere-Music-Player/SwiftTagLib.cpp
- AVFoundation `AVMetadataItem`: https://developer.apple.com/documentation/avfoundation/avmetadataitem
- AVFoundation ID3 metadata identifiers: https://developer.apple.com/documentation/avfoundation/avmetadataidentifier
- ID3v2.4 frames: https://id3.org/id3v2.4.0-frames
- ID3v2.4 structure: https://id3.org/id3v2.4.0-structure
