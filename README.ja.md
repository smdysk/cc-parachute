# 🪂 cc-parachute

**Claude Code のコンテキスト圧縮からの軟着陸。**

`/compact`（さらに厄介なのは auto-compact）はセッションを要約する際に、
**判断構造**を静かに落とします。なぜその案を採ったのか、何を却下しなぜ却下
したのか、いまどのフェーズにいるのか、実行前に何を検証すると約束していたのか。
圧縮の10分後、エージェントは1時間前に葬った案を再提案したり、「検証してから」
と合意していた手順を親切心で実行したりします。

cc-parachute はそれを **小さなシェルフック4本とスキル1つ** で圧縮から守ります。
追加のLLM呼び出しなし、APIキー不要、常駐プロセスなし。自動化も込みです:
使用率85%を超えるとセッション自身が自分のstateを保存するよう指示され、
何も保存されないまま圧縮が来ても機械式の事実スナップショットが残ります——
すべて追加コストゼロのまま。

## 構成

| 部品 | 動くタイミング | 役割 |
|---|---|---|
| `statusline.sh` | 常時 | `[Opus] myproject \| ctx 62% ⚠ /compact-prep` — 使用率メーター。60%で警告、85%でauto-prep起動 |
| `userpromptsubmit-notify.sh` | 毎ターン | 60%: `/compact-prep` を一度だけ提案。85%: セッション自身に「今すぐstateを書け」と指示 |
| `/compact-prep` スキル | 手動起動（またはauto-prep経由） | 9見出しのstateファイルを保存: 採用/却下と理由・制約・次の一手 |
| `precompact-backup.sh` | 圧縮時 | rawトランスクリプト退避、auto-compactに印、state未保存なら機械式の事実スナップショットを生成 |
| `sessionstart-recovery.sh` | 圧縮直後 | 最良のstate（本命 > フォルダ名フォールバック > 機械式）＋懐疑ガードレールを注入 |

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
   │  ctx ≥ 60% → markers/<sid>.warn     ctx ≥ 85% → markers/<sid>.autoprep
   ▼
userpromptsubmit-notify.sh（次のプロンプト）
   │  60%: 一度だけのリマインダー — 区切りで /compact-prep を提案
   │  85%: 指示 — セッション自身が今すぐstateファイルを書いてから
   │       ユーザーの依頼を続行（正確な保存先パスはフックが手渡す）
   ▼
/compact-prep（あなた、または auto-prep 指示）
   │  compact-state/<session>.md を書く — 判断・却下理由・次の一手
   ▼
/compact 実行（または auto-compact 発火）
   │  precompact-backup.sh がトランスクリプト退避、autoなら印、
   │  state未保存なら <session>.auto.md（機械式の事実）を生成
   ▼
sessionstart-recovery.sh（SessionStart, matcher "compact"）
      最良のstate（本命 > フォルダ名 > 機械式）＋懐疑ガードレールを注入し、
      クールダウンをリセット
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

- **追加コストゼロ。** stateファイルはセッション自身がスキルに従って書く——
  自動化層もこの原則のまま: 85%の指示は「セッション自身に書かせる」、圧縮時の
  フォールバックは純シェル。二次LLM呼び出しなし、APIキー不要、
  要約を要約するためのトークン消費なし。
- **fail-open。** 全フックは何があっても exit 0。マーカー破損やファイル欠落は
  「警告が出ない」に劣化するだけで、セッションを止めることはない。
- **監査可能。** 4スクリプト合計 約270行のbash。`settings.json` に触らせる前に
  10分で全部読める（バックアップも取る）。
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
| 準備なしのauto-compact | 85%でauto-prep指示＋圧縮時の機械式スナップショット | LLM生成state |
| フットプリント | シェル4本＋スキル1つ | フルプラグイン |
| Windows | 一級対応・CIで検証 | 記載なし |

トランスクリプト全体のLLM生成サマリーとプラグイン形式なら compact-plus を、
セッション自身が書く一次情報のstate・auto-compactの自動カバー・追加トークン
ゼロ・Windows一級対応なら cc-parachute を選んでください。

## FAQ

**`/compact-prep` は手動なの?**
いいえ——3層でカバーされます。60%で提案、85%でセッション自身が即座に
stateファイルを書くよう指示（追加呼び出しゼロのまま。フックが正確な保存先
パスを手渡します）、それでも何も保存されないまま圧縮が来たらPreCompactフックが
機械式スナップショットを残します。とはいえ、作業の区切りで意図的に打つ
`/compact-prep` が最良のstateを生みます——自動化層は理想でなくセーフティネットです。

**何も保存されないまま圧縮された場合は?**
機械式スナップショット（git status・直近の発言・触ったファイル）が
「事実のみ」ラベル付きで注入され、懐疑ガードレールが適用されます。raw
トランスクリプトの退避は `~/.claude/compact-state/transcripts/` に。
どのフォールバックでも救えないのは「書き残されなかった判断構造」で、
それを防ぐのが85%指示の役割です。

**同じフォルダで複数セッションを並走させていたら?**
state保存については完全対応ではありません。ポインタは「最後にプロンプトを
送ったセッション」を指します。`/compact-prep` の起動自体でポインタは自分に
更新されますが、その数秒の間に別セッションがプロンプトを送るとレースに負け、
stateファイルが別セッション名で保存されえます。`/compact-prep` を使う
セッションはフォルダを分けるのが確実です。

**データはどこへ行く?**
どこへも。すべて手元の `~/.claude/compact-state/` 内に留まります。
退避は自動ローテーション（セッションごと5世代・7日）。スキルには
「stateファイルに秘密情報を書かない」ハードゲートがあります。

**閾値を変えたい**
Claude Code を起動する環境で `CC_PARACHUTE_THRESHOLD`（既定60、提案）と
`CC_PARACHUTE_AUTOPREP_THRESHOLD`（既定85、即時保存指示）を設定。

**アンインストール**
`settings.json` のバックアップを書き戻す（またはフック3エントリと
statuslineを削除）→ `~/.claude/hooks/cc-parachute/`・
`~/.claude/skills/compact-prep/`・`~/.claude/compact-state/` を削除。

## コントリビュート

歓迎します — 設計ルール（fail-open・依存はjqのみ）と good first issue の
一覧は [CONTRIBUTING.md](CONTRIBUTING.md) へ。テストは
`bash test/run-tests.sh`（54チェック・ネットワーク不要）。

## ライセンス

[MIT](LICENSE) © 2026 Shimady
