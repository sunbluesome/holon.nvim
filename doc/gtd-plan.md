# holon.nvim GTD機能 実装計画

## Context

holon.nvimにGTD機能を追加する。
Zettelkastenノートをタスクとして管理し、lazygit風の3パネルUIで
ステータス管理・タイムライン可視化・依存関係追跡を実現する。

リポジトリ名・Lua名前空間は holon.nvim / holon のまま維持。
GTDコードは `lua/holon/gtd/` に配置し、`:HolonGtd` で起動する。
遅延ロードにより、GTDを使わないユーザーへの影響はゼロ。

---

## データモデル

### frontmatter拡張

既存テンプレートにGTDフィールドを追加する。専用テンプレートは作らない。

**現在の project.md (`personal-knowledge/.foam/templates/project.md`):**
```yaml
---
title: ${UUID}
created: ${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE}T${CURRENT_HOUR}:${CURRENT_MINUTE}:${CURRENT_SECOND}
lastmod: ${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE}T${CURRENT_HOUR}:${CURRENT_MINUTE}:${CURRENT_SECOND}
url: null
type: project
tags:
    - null
---
```

**GTDフィールド追加後:**
```yaml
---
title: ${UUID}
created: ${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE}T${CURRENT_HOUR}:${CURRENT_MINUTE}:${CURRENT_SECOND}
lastmod: ${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DATE}T${CURRENT_HOUR}:${CURRENT_MINUTE}:${CURRENT_SECOND}
url: null
type: project
status: inbox
start_date: null
target_date: null
blocked_by: null
tags:
    - null
---
```

**追加フィールド:**

| フィールド | 型 | 説明 |
|-----------|------|------|
| `status` | string | inbox / todo / inprogress / waiting / delegate / done |
| `start_date` | date (YYYY-MM-DD) | 着手予定日 |
| `target_date` | date (YYYY-MM-DD) | 期限日 |
| `blocked_by` | wikilink[] | ブロッカーへのwikilink参照 |

- `status` を持つノート = GTDタスク（`type` とは直交）
- GTD管理したいテンプレートにだけ `status` を追加すればよい（permanent等は不要）
- 番号 (#1, #2...) はfrontmatterに保存しない。ボード表示時にランタイム割り当て
- `blocked_by` はwikilink形式で永続参照、表示上はランタイム番号

### タイムホライズン算出

| ホライズン | 条件 |
|-----------|------|
| overdue | target_date < today |
| today | target_date == today |
| 1w | today < target_date <= today + 7 |
| 2w | today + 7 < target_date <= today + 14 |
| 1m | today + 14 < target_date <= today + 30 |
| 2m | today + 30 < target_date <= today + 60 |
| later | target_date > today + 60 |
| no target | target_date フィールドなし |

---

## UI設計

### 3パネル + ヘルプライン

```
┌─ Filter ──────┬─ Tasks ─────────────────┬─ Timeline ──────────────┐
│ > inbox     (3)│ #1 API設計        3/15 │   ┃ ░░░░░░░░░█          │
│   todo      (2)│ #2 データソース        │   ┃                      │
│   progress  (1)│ #3 メール返信     3/10 │   ┃ ░░░█                 │
│   waiting   (1)│ #4 DB移行 🔒#1,#2 3/10 │   ┃     ░░░█             │
│   delegate  (0)│                        │   ┃                      │
│   done     (12)│                        │   ┃                      │
├───────────────┴─────────────────────────┴──────────────────────────┤
│ j/k:移動 Tab:パネル h/l:ステータス変更 CR:開く t:target s:start H:Horizon│
└────────────────────────────────────────────────────────────────────┘
```

- 左: フィルタ軸（Status / Horizon を `S`/`H` でトグル切替）
- 中央: タスク一覧（もう一方の軸を属性として行内表示）
- 右: タイムライン（start_date〜target_date バー + 今日ライン）
- 下: コンテキスト依存ヘルプライン（フォーカス中パネルに応じて表示変更）

### 操作体系

| キー | パネル | 動作 |
|------|--------|------|
| `j`/`k` | 全パネル | 上下移動 |
| `Tab`/`S-Tab` | 全体 | パネルフォーカス移動 |
| `CR` | Filter | フィルタ選択 → Tasks再描画 |
| `CR` | Tasks | ノートを開く（ボードを閉じる） |
| `h`/`l` | Tasks | ステータスを前/次へ変更（frontmatter即更新） |
| `t` | Tasks | target_date を設定（カレンダーピッカー） |
| `s` | Tasks | start_date を設定（カレンダーピッカー） |
| `S` | Filter | Status表示に切替 |
| `H` | Filter | Horizon表示に切替 |
| `q`/`Esc` | 全体 | ボードを閉じる |

### 表示モード

**Status表示時のタスク行:**
```
#1 API設計の調査        today  project  3/15
#2 DB移行 🔒#1,#3       1w     project  3/10
```

**Horizon表示時のタスク行:**
```
#1 API設計の調査        inbox  project  3/15
#2 DB移行 🔒#1,#3       todo   project  3/10
```

---

## モジュール構成

### 新規ファイル

```
lua/holon/gtd/
  board.lua      -- ボード開閉、ウィンドウレイアウト、キーバインド
  state.lua      -- 状態管理（フォーカス、選択、ビューモード、ランタイム番号）
  render.lua     -- 3パネル + ヘルプラインの描画（バッファ書き込み + extmarks）
  timeline.lua   -- タイムラインASCII描画エンジン
```

### 既存ファイル変更

| ファイル | 変更内容 |
|---------|---------|
| `lua/holon/frontmatter.lua` | `set_field()`, `add_to_array()`, `remove_from_array()` 追加 |
| `lua/holon/finders.lua` | `find_tasks()`, `collect_statuses()`, `collect_horizons()` 追加 |
| `lua/holon/config.lua` | `gtd` 設定セクション追加 |
| `lua/holon/init.lua` | `gtd` を遅延ロード対象に追加 |
| `plugin/holon.lua` | `:HolonGtd` コマンド追加 |

### 再利用する既存関数

| 関数 | ファイル | 用途 |
|------|---------|------|
| `frontmatter.parse_file()` | frontmatter.lua | タスクメタデータ読み取り |
| `frontmatter.get_title/type/tags()` | frontmatter.lua | 表示情報取得 |
| `finders.list_files()` (内部) | finders.lua | ファイル一覧取得 |
| `links.resolve_link_target()` | links.lua | blocked_by wikilink解決 |
| `utils.read_file/write_file()` | utils.lua | frontmatter書き換え時のI/O |
| `utils.local_date()` | utils.lua | ホライズン算出の現在日付 |
| `config.get()` | config.lua | GTD設定値の取得 |
| `config.setup_highlights()` パターン | config.lua | GTDステータス用ハイライト定義 |

---

## 実装フェーズ

### Phase 1: frontmatter書き込み基盤

`lua/holon/frontmatter.lua` に追加:

- `M.set_field(content, key, value)` -- 行レベル置換（serialize/deserializeではない）
- `M.add_to_array(content, key, value)` -- 配列に項目追加
- `M.remove_from_array(content, key, value)` -- 配列から項目削除

方針: 元のフォーマット（インデント、順序）を最大限保持する行操作。
既存パーサは変更不要（status/target_date/start_date/blocked_byは既存のkey-value/array解析で取得可能）。

### Phase 2: GTD設定・データ取得

`lua/holon/config.lua` に `gtd` セクション追加:
- statuses リスト、status_icons、blocked_icon
- layout (width, height, filter_width, timeline_width)

`lua/holon/finders.lua` に追加:
- `M.find_tasks(opts)` -- statusフィールドを持つノートを取得
- `M.collect_statuses(opts)` -- ステータス別集計
- `M.collect_horizons(opts)` -- ホライズン別集計

既存の `list_files()` + `frontmatter.parse_file()` パターンを再利用。

### Phase 3: ボード状態管理

`lua/holon/gtd/state.lua`:
- view_mode (status/horizon)、filter_index、task_index、active_panel
- 全タスクスキャン → ランタイム番号割り当て（ソート: status順 → target_date順 → title順）
- blocked_by wikilink → ランタイム番号の解決（links.resolve_link_target() 利用）

### Phase 4: ボードUI

`lua/holon/gtd/board.lua`:
- `nvim_open_win` でフローティングウィンドウ（外枠）作成
- 内部に4バッファ: filter, tasks, timeline, helpline
- `buftype=nofile`, `modifiable=false`
- パネルフォーカス変更時にボーダーハイライト切替 + ヘルプライン更新

`lua/holon/gtd/render.lua`:
- `render_filter(buf, state)` -- ステータス/ホライズンリスト + 件数
- `render_tasks(buf, state)` -- タスク行（番号、タイトル、属性、due、ブロック表示）
- `render_timeline(buf, state)` -- timeline.lua に委譲
- `render_helpline(buf, state)` -- フォーカスパネルに応じたキー説明

extmarks + highlight groups で色付け。選択行ハイライト。

### Phase 5: タイムライン描画

`lua/holon/gtd/timeline.lua`:
- 表示範囲: 表示中タスクのstart_date/target_dateを含む範囲を自動算出
- 今日ライン (`┃`) 固定表示
- タスク行と中央パネルの行が1:1対応
- `░` = start_date〜target_date期間、`█` = target_date当日
- スケール自動調整（2週間以内: 日単位、月をまたぐ: 週単位）

### Phase 6: 統合

- `plugin/holon.lua` に `:HolonGtd` コマンド追加
- `lua/holon/init.lua` に gtd モジュール遅延ロード追加
- `personal-knowledge/.foam/templates/project.md` にGTDフィールドを追加
  （データモデルのbefore/after参照）

---

## 追加の外部依存

なし。`nvim_open_win` で自前UI構築。

---

## 検証方法

1. `:HolonGtd` でボードが開き、`q` で閉じること
2. 左パネルでステータス選択 → 中央パネルがフィルタされること
3. `S`/`H` でStatus/Horizon表示が切り替わること
4. `h`/`l` でステータス変更 → frontmatterが即更新されること
5. `t`/`s` でtarget_date/start_date設定 → タイムラインが更新されること
6. `CR` でノートが開くこと
7. `blocked_by` wikilink → ランタイム番号表示が正しいこと
8. タイムラインにstart_date〜target_dateバー + 今日ラインが描画されること
9. ヘルプラインがフォーカスパネルに応じて変わること
10. 既存Zettelkasten機能 (v0.1.0) に影響がないこと
