-- DMG のウィンドウの見た目を Finder に設定させる（release.sh から呼ぶ）。
-- 使い方: osascript scripts/dmg/layout.applescript <マウントした場所（/Volumes/Macorn など）>
-- 同じ名前の DMG がほかに開いていても取り違えないよう、名前ではなく場所で指す。
-- 背景（make-background.swift）の矢印の左右にアイコンが来るよう、位置をそろえる。
on run argv
	set mountPoint to (POSIX file (item 1 of argv)) as alias
	tell application "Finder"
		tell (item mountPoint)
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			-- 中身が 660×400 になるよう、タイトルバーとツールバーの分だけ高くする（macOS 26 ではツールバーを隠せない）
			set the bounds of container window to {200, 120, 860, 600}
			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 128
			set text size of viewOptions to 13
			set label position of viewOptions to bottom
			set shows item info of viewOptions to false
			set background picture of viewOptions to file ".background:background.tiff"
			-- Finder の位置はアイコンの中心より少し上を指すので、矢印（上から 200）より 45 上にする
			set position of item "Macorn.app" of container window to {170, 155}
			set position of item "Applications" of container window to {490, 155}
			-- 隠しファイルを表示する設定の人にも見えにくいよう、下の見えない所へ置く
			try
				set position of item ".background" of container window to {170, 640}
			end try
			close
			open
			update without registering applications
			delay 2
			close
		end tell
	end tell
end run
