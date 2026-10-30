-- =====================================================================
--  煌桜会ポータル（イントラネット）スキーマ
--  有給管理アプリと同じ Supabase プロジェクト（usdgadreruepqphqlcno）に追加する。
--  アカウント・profiles は有給管理と共用。閲覧用(viewer)アカウントは利用不可。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. メンバー判定（staff / admin かつ在籍中のみ）
-- ---------------------------------------------------------------------
create or replace function public.portal_is_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('staff','admin') and active
  );
$$;

-- ---------------------------------------------------------------------
-- 1. お知らせ（掲示板）
-- ---------------------------------------------------------------------
create table if not exists public.portal_posts (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  body       text not null default '',
  category   text not null default '連絡'
             check (category in ('重要','連絡','研修','行事','その他')),
  pinned     boolean not null default false,
  author_id  uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.portal_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.portal_posts(id) on delete cascade,
  body       text not null,
  author_id  uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.portal_reads (
  post_id uuid not null references public.portal_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  read_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- ---------------------------------------------------------------------
-- 2. マニュアル・共有ノート（誰でも作成・編集）
-- ---------------------------------------------------------------------
create table if not exists public.portal_pages (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  category   text not null default 'その他',
  body       text not null default '',
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  updated_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. リンク集
-- ---------------------------------------------------------------------
create table if not exists public.portal_links (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  url         text not null,
  description text,
  category    text not null default 'その他',
  sort        int not null default 100,
  created_by  uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 4. 共有ファイル（実体は Storage バケット portal-files）
-- ---------------------------------------------------------------------
create table if not exists public.portal_files (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  path        text not null unique,
  size        bigint,
  mime        text,
  category    text not null default 'その他',
  note        text,
  uploaded_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 5. RLS
-- ---------------------------------------------------------------------
alter table public.portal_posts    enable row level security;
alter table public.portal_comments enable row level security;
alter table public.portal_reads    enable row level security;
alter table public.portal_pages    enable row level security;
alter table public.portal_links    enable row level security;
alter table public.portal_files    enable row level security;

-- お知らせ: 閲覧・投稿=メンバー / 編集・削除=投稿者か管理者
drop policy if exists posts_select on public.portal_posts;
create policy posts_select on public.portal_posts for select using (public.portal_is_member());
drop policy if exists posts_insert on public.portal_posts;
create policy posts_insert on public.portal_posts for insert
  with check (public.portal_is_member() and author_id = auth.uid());
drop policy if exists posts_update on public.portal_posts;
create policy posts_update on public.portal_posts for update
  using (public.portal_is_member() and (author_id = auth.uid() or public.is_admin()));
drop policy if exists posts_delete on public.portal_posts;
create policy posts_delete on public.portal_posts for delete
  using (public.portal_is_member() and (author_id = auth.uid() or public.is_admin()));

-- コメント
drop policy if exists comments_select on public.portal_comments;
create policy comments_select on public.portal_comments for select using (public.portal_is_member());
drop policy if exists comments_insert on public.portal_comments;
create policy comments_insert on public.portal_comments for insert
  with check (public.portal_is_member() and author_id = auth.uid());
drop policy if exists comments_delete on public.portal_comments;
create policy comments_delete on public.portal_comments for delete
  using (public.portal_is_member() and (author_id = auth.uid() or public.is_admin()));

-- 既読: 誰が読んだかは全員見える / 登録は本人のみ
drop policy if exists reads_select on public.portal_reads;
create policy reads_select on public.portal_reads for select using (public.portal_is_member());
drop policy if exists reads_insert on public.portal_reads;
create policy reads_insert on public.portal_reads for insert
  with check (public.portal_is_member() and user_id = auth.uid());

-- マニュアル: 閲覧・作成・編集=メンバー / 削除=作成者か管理者
drop policy if exists pages_select on public.portal_pages;
create policy pages_select on public.portal_pages for select using (public.portal_is_member());
drop policy if exists pages_insert on public.portal_pages;
create policy pages_insert on public.portal_pages for insert with check (public.portal_is_member());
drop policy if exists pages_update on public.portal_pages;
create policy pages_update on public.portal_pages for update
  using (public.portal_is_member()) with check (public.portal_is_member() and updated_by = auth.uid());
drop policy if exists pages_delete on public.portal_pages;
create policy pages_delete on public.portal_pages for delete
  using (public.portal_is_member() and (created_by = auth.uid() or public.is_admin()));

-- リンク集
drop policy if exists links_select on public.portal_links;
create policy links_select on public.portal_links for select using (public.portal_is_member());
drop policy if exists links_insert on public.portal_links;
create policy links_insert on public.portal_links for insert with check (public.portal_is_member());
drop policy if exists links_update on public.portal_links;
create policy links_update on public.portal_links for update
  using (public.portal_is_member() and (created_by = auth.uid() or public.is_admin()));
drop policy if exists links_delete on public.portal_links;
create policy links_delete on public.portal_links for delete
  using (public.portal_is_member() and (created_by = auth.uid() or public.is_admin()));

-- ファイル
drop policy if exists files_select on public.portal_files;
create policy files_select on public.portal_files for select using (public.portal_is_member());
drop policy if exists files_insert on public.portal_files;
create policy files_insert on public.portal_files for insert
  with check (public.portal_is_member() and uploaded_by = auth.uid());
drop policy if exists files_delete on public.portal_files;
create policy files_delete on public.portal_files for delete
  using (public.portal_is_member() and (uploaded_by = auth.uid() or public.is_admin()));

-- ---------------------------------------------------------------------
-- 6. Storage バケット（非公開・1ファイル50MBまで）
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('portal-files', 'portal-files', false, 52428800)
on conflict (id) do nothing;

drop policy if exists portal_files_read on storage.objects;
create policy portal_files_read on storage.objects for select
  using (bucket_id = 'portal-files' and public.portal_is_member());
drop policy if exists portal_files_write on storage.objects;
create policy portal_files_write on storage.objects for insert
  with check (bucket_id = 'portal-files' and public.portal_is_member());
drop policy if exists portal_files_remove on storage.objects;
create policy portal_files_remove on storage.objects for delete
  using (bucket_id = 'portal-files' and public.portal_is_member()
         and (owner = auth.uid() or public.is_admin()));

-- ---------------------------------------------------------------------
-- 7. 初期データ
-- ---------------------------------------------------------------------
insert into public.portal_links (title, url, description, category, sort, created_by)
select v.title, v.url, v.description, v.category, v.sort,
       (select id from public.profiles where email = 's399035u@gmail.com')
from (values
  ('有給管理', 'https://s399035u-boop.github.io/yukyu-kanri/', '休暇の取得・残日数・共有カレンダー（同じアカウントでログイン）', '院内アプリ', 10),
  ('来院前Web問診（患者用）', 'https://s399035u-boop.github.io/web-monshin/', '患者さんに案内するURL', '院内アプリ', 20),
  ('Web問診（医師用）', 'https://s399035u-boop.github.io/web-monshin/#doctor', '問診サマリーの確認（パスコードが必要）', '院内アプリ', 30),
  ('唐人町ハートクリニック（開院予告）', 'https://tojinmachi-heart.com', '2027年4月開院予定', '外部サイト', 120)
) as v(title, url, description, category, sort)
where not exists (select 1 from public.portal_links);

insert into public.portal_pages (title, category, body, created_by, updated_by)
select v.title, v.category, v.body, a.id, a.id
from (values
  ('RULE-1 遅刻時の連絡', '勤怠・休暇',
   E'## 結論\n遅刻する場合は、**始業時刻より前に院長へLINEで連絡**する。院長が不在のときは**理事長へ連絡**する。\n\n## 詳細・手順\n- 遅刻がわかった時点で、始業前に院長へ連絡する\n- 連絡手段：LINE\n\n## 例外・注意点\n- 院長が不在のときは、理事長へ連絡する\n\n## 改定履歴\n- 2026-10-15 制定\n- 2026-10-16 連絡手段（LINE）と院長不在時の連絡先（理事長）を追記'),
  ('このポータルの使い方', 'はじめに',
   E'## できること\n- **お知らせ**：連絡事項の掲示。読んだら「既読にする」を押す。コメントもできる\n- **マニュアル**：院内ルール・手順書。誰でも追加・編集できる\n- **ファイル**：PDF・Excel・画像などの共有\n- **リンク**：有給管理などよく使うページへの入口\n\n## 注意\n- 患者さんの氏名・カルテ情報など個人情報は書き込まない\n- パスワードは有給管理と同じ')
) as v(title, category, body)
cross join (select id from public.profiles where email = 's399035u@gmail.com') a
where not exists (select 1 from public.portal_pages);
