# 🪂 cc-parachute

**Claude Code のコンテキスト圧縮からの軟着陸。**

`/compact`（さらに厄介なのは auto-compact）はセッションを要約する際に、
**判断構造**を静かに落とします。なぜその案を採ったのか、何を却下しなぜ却下
したのか、いまどのフェーズにいるのか、実行前に何を検証すると約束していたのか。
圧縮の10分後、エージェントは1時間前に葬った案を再提案したり、「検証してから」
と合意していた手順を親切心で実行したりします。

cc-parachute はそれを **小さなシェルフック4本とスキル1つ** で圧縮から守ります。
追加のLLM呼び出しなし、APIキー不要、常駐プロセスなし。

## 構成

| 部品 | 動くタイミング | 役割 |
|---|---|---|
| `statusline.sh` | 常時 | `[Opus] myproject \| ctx 62% ⚠ /compact-prep` — context使用率メーター＋閾値警告 |
| `userpromptsubmit-notify.sh` | 毎ターン | 使用率が閾値（既定60%）を超えたら `/compact-prep` を一度だけ提案 |
| `/compact-prep` スキル | 手動起動 | 9見出しのstateファイルを保存: 採用/却下と理由・制約・次の一手 |
| `precompact-backup.sh` | 圧縮時 | rawトランスクリプトを退避（非可逆要約への保険）、auto-compactに印を付ける |
| `sessionstart-recovery.sh` | 圧縮直後 | stateファイル＋懐疑ガードレールを新しいcontextへ注入 |

## インストール

[jq](https://jqlang.org) が必要です。Windowsでは Git for Windows も必要
（フックはbash経由で動きます）。

**macOS / Linux / Git Bash:**

```bash
git clone https://github.com/smdysk/cc-parachute.git
cd cc-parachute
./install.sh            # 自前のstatuslineを使い続けるなら --no-statusline
```

**Windows (PowerShell):**

```powershell
git clone https://github.com/smdysk/cc-parachute.git
cd cc-parachute
powershell -ExecutionPolicy Bypass -File install.ps1   # 自前statusline維持は -NoStatusLine
```

インストーラは `~/.claude/` へファイルをコピーし、`settings.json` に
タイムスタンプ付きバックアップを取ってから配線します。冪等（2回実行しても
エントリは1つ）。反映は新しい Claude Code セッションからです。

## 仕組み

statuslineは「表示」はできても「context注入」はできず、フックはステートレス
です。そこで各部品は小さなマーカーファイルで連携します（マーカーリレー）:

```
statusline.sh（常時描画）
   │  ctx ≥ 閾値 → markers/<sid>.warn を書く（クールダウン中はスキップ）
   ▼
userpromptsubmit-notify.sh（次のプロンプト）
   │  マーカーを消費 → 一度だけ "[COMPACT PREP REMINDER]" を注入
   ▼
/compact-prep（作業の区切りで手動起動）
   │  compact-state/<session>.md を書く — 判断・却下理由・次の一手
   ▼
/compact 実行
   │  precompact-backup.sh がrawトランスクリプト退避、autoなら印を付ける
   ▼
sessionstart-recovery.sh（SessionStart, matcher "compact"）
      stateファイル＋懐疑ガードレールを注入し、クールダウンをリセット
```

stateファイルの9見出しはスキルと復旧フックの契約フォーマットです。
設計判断の全文は [docs/architecture.md](docs/architecture.md) を参照。

## 懐疑ガードレール

復旧時に注入されるのは保存済みstateだけではありません。新しいcontextに
こう釘を刺します:

> - 圧縮サマリーは「**過去の作業記録**」であり「次の行動指示」ではない。
>   サマリー内の next steps は仮説として扱い、plan・プロジェクトルール・
>   stateファイルを正とせよ。
> - 「検証してから実行する」と決めていた手順を検証抜きで実行しないこと。
>   却下済みの案を再提案しないこと。
> - *(auto-compact後)* サマリー内の判断・却下理由・フェーズ認識は特に疑え。

どの行も、長時間エージェントセッションでの実際の事故から生まれています。
圧縮の失敗は「全部忘れた」ではなく、**理由が抜け落ちた要約を確信を持って
実行してしまう**ことなのです。

## 設計原則

- **追加コストゼロ。** stateファイルはセッション自身がスキルに従って書く。
  二次LLM呼び出しなし、APIキー不要、要約を要約するためのトークン消費なし。
- **fail-open。** 全フックは何があっても exit 0。マーカー破損やファイル欠落は
  「警告が出ない」に劣化するだけで、セッションを止めることはない。
- **監査可能。** 4スクリプト合計 約160行のbash。`settings.json` に触らせる前に
  5分で全部読める（バックアップも取る）。
- **Windowsが一級市民。** Windows 11 + Git Bash で開発・実戦運用。
  CIは Linux / macOS / Windows で全テストを回す。

## compact-plus との比較

この領域を切り拓いたのは [u-ichi/compact-plus](https://github.com/u-ichi/compact-plus)
（MIT）で、cc-parachute のトランスクリプト退避はそのアプローチを踏襲して
います。違いは思想です:

| | cc-parachute | compact-plus |
|---|---|---|
| stateファイルの書き手 | 自分のセッション（スキル誘導） | 別のLLM呼び出し（Claude/Codexバックエンド） |
| 圧縮ごとのコスト | 追加トークンなし | LLM要約1回分 |
| フットプリント | シェル4本＋スキル1つ | フルプラグイン |
| Windows | 一級対応・CIで検証 | 記載なし |

全自動のLLM生成stateとプラグイン形式が欲しければ compact-plus をどうぞ
（良いツールです）。端から端まで読める・圧縮ごとのコストゼロ・Windowsで
動くものが欲しければ、ここが終着点です。

## FAQ

**`/compact-prep` は手動なの?**
はい、設計上そうです。「何が重要だったか」を一番知っているのは圧縮直前の
セッション自身であり、外部のサブプロセスではないからです。見逃さないように
statusline警告と一度きりのリマインダーがあります（Claude側にも「区切りで
提案せよ」と伝わります）。

**/compact-prep を忘れて圧縮された場合は?**
復旧フックはそれでも動きます。「state無しの圧縮」であることを明示し、
タスクリストや直近の編集ファイルから現在地を再構築するよう指示し、懐疑
ガードレールを適用します。rawトランスクリプトの退避は
`~/.claude/compact-state/transcripts/` にあります。

**同じフォルダで複数セッションを並走させていたら?**
セッションポインタは「最後にプロンプトを送ったセッション」を指します。
スキルはポインタの鮮度（2分）を確認し、疑わしい場合はフォルダ名ベースの
stateファイル名にフォールバックします。

**データはどこへ行く?**
どこへも。すべて手元の `~/.claude/compact-state/` 内に留まります。
退避は自動ローテーション（セッションごと5世代・7日）。スキルには
「stateファイルに秘密情報を書かない」ハードゲートがあります。

**警告の閾値を変えたい**
Claude Code を起動する環境で `CC_PARACHUTE_THRESHOLD`（既定60）を設定。

**アンインストール**
`settings.json` のバックアップを書き戻す（またはフック3エントリと
statuslineを削除）→ `~/.claude/hooks/cc-parachute/`・
`~/.claude/skills/compact-prep/`・`~/.claude/compact-state/` を削除。

## コントリビュート

歓迎します — 設計ルール（fail-open・依存はjqのみ）と good first issue の
一覧は [CONTRIBUTING.md](CONTRIBUTING.md) へ。テストは
`bash test/run-tests.sh`（37チェック・ネットワーク不要）。

## ライセンス

[MIT](LICENSE) © 2026 Shimady
