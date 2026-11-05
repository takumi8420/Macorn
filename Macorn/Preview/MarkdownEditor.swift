import WebKit

/// Markdown のプレビューを、その場で書き換えられるようにする（Notion のように）
///
/// - 表示中の Markdown のページに、編集用のスクリプトを差し込む。ファイルに書かれたスクリプトは止めたまま、
///   このスクリプトだけをアプリ専用の場所（WKContentWorld）で動かす
/// - 「# 」「- 」「1. 」「> 」「[] 」「```」「---」や `**太字**` などの Markdown の書き方は、打った時点でその見た目に変わる
/// - 書き換えたブロックだけを Markdown に戻し、触っていないブロックは元の文章のまま残す（ファイルの書き方を崩さない）
/// - 少し手を止めたら自動で保存する
enum MarkdownEditor {
    /// 編集用のスクリプトを動かす場所（ページのスクリプトとは別）
    static let world = WKContentWorld.world(name: "macorn-markdown-editor")
    /// スクリプトからアプリへの知らせの名前
    static let messageName = "macornEditor"

    static var userScript: WKUserScript {
        WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world)
    }

    /// 編集中の見た目（Markdown のページの style に足す）
    static let style = """
    body[contenteditable] { outline: none; caret-color: var(--accent); min-height: 100vh; box-sizing: border-box; }
    body.md-empty::before { content: "ここに入力（「# 」で見出し、「- 」でリスト、「[] 」でチェックリスト）"; color: var(--muted); position: absolute; pointer-events: none; }
    .md-block[data-raw] { cursor: default; border-radius: 4px; }
    .md-block[data-raw]:hover { outline: 1px dashed var(--border); outline-offset: 4px; }
    pre.md-raw { white-space: pre-wrap; }
    li.task > input { cursor: pointer; }
    a { cursor: text; }
    """

    static let script = #"""
    (() => {
      const data = document.querySelector('meta[name="macorn-md"]');
      if (!data || window.__macornEditor) return;
      const payload = JSON.parse(data.content);
      if (!payload.editable) return;
      window.__macornEditor = true;
      const model = payload.document;
      const post = (message) => {
        message.path = payload.path;
        window.webkit.messageHandlers.macornEditor.postMessage(message);
      };
      const root = document.body;
      document.execCommand('defaultParagraphSeparator', false, 'p');
      root.contentEditable = 'true';
      root.spellcheck = false;
      if (!root.querySelector('.md-block')) {
        const p = document.createElement('p');
        p.appendChild(document.createElement('br'));
        root.appendChild(p);
      }
      root.querySelectorAll('li.task > input[type=checkbox]').forEach((box) => box.removeAttribute('disabled'));
      root.querySelectorAll('.md-block[data-raw]').forEach((block) => { block.title = 'ダブルクリックで HTML を編集'; });

      // MARK: Markdown に戻す

      const clean = (text) => text.replace(/ /g, ' ').replace(/​/g, '');
      const BLOCK = new Set(['P', 'DIV', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'UL', 'OL', 'LI', 'PRE', 'BLOCKQUOTE',
        'TABLE', 'HR', 'DETAILS', 'SECTION', 'FIGURE']);
      const isBlock = (node) => node.nodeType === 1 && BLOCK.has(node.tagName);

      // 前後の空白は記号の外に出す（「** 太字**」にならないように）
      const wrap = (text, mark) => {
        if (!text.trim()) return text;
        const m = text.match(/^(\s*)([\s\S]*?)(\s*)$/);
        return m[1] + mark + m[2] + mark + m[3];
      };

      function inline(node) {
        let out = '';
        node.childNodes.forEach((child) => {
          if (child.nodeType === 3) { out += clean(child.nodeValue); return; }
          if (child.nodeType !== 1) return;
          switch (child.tagName) {
            case 'STRONG': case 'B': out += wrap(inline(child), '**'); break;
            case 'EM': case 'I': out += wrap(inline(child), '*'); break;
            case 'DEL': case 'S': case 'STRIKE': out += wrap(inline(child), '~~'); break;
            case 'CODE': {
              const text = clean(child.textContent);
              if (text) out += text.includes('`') ? '`` ' + text + ' ``' : '`' + text + '`';
              break;
            }
            case 'A': {
              const href = child.getAttribute('href') || '';
              const text = inline(child);
              out += (text === href && /^https?:/.test(href)) ? href : '[' + text + '](' + href + ')';
              break;
            }
            case 'IMG': out += '![' + (child.getAttribute('alt') || '') + '](' + (child.getAttribute('src') || '') + ')'; break;
            case 'BR': if (child.nextSibling) out += '  \n'; break;
            case 'INPUT': break;
            case 'SPAN': case 'FONT': out += inline(child); break;
            default:
              if (isBlock(child)) {
                out += (out && !out.endsWith('\n') ? '\n' : '') + block(child);
              } else {
                const tag = child.tagName.toLowerCase();
                out += '<' + tag + '>' + inline(child) + '</' + tag + '>';
              }
          }
        });
        return out;
      }

      // 中のブロックを順に。ブロックでないもの（文字・強調など）が続くところは、1つの段落にまとめる
      function blocks(container, joiner = '\n\n') {
        const parts = [];
        let run = null;
        const flush = () => {
          if (!run) return;
          const text = inline(run).trim();
          if (text) parts.push(text);
          run = null;
        };
        container.childNodes.forEach((child) => {
          if (isBlock(child)) {
            flush();
            const text = block(child);
            if (text.trim()) parts.push(text);
          } else if (!(child.nodeType === 1 && child.tagName === 'INPUT')) {
            if (!run) run = document.createElement('span');
            run.appendChild(child.cloneNode(true));
          }
        });
        flush();
        return parts.join(joiner);
      }

      function block(node) {
        if (node.nodeType === 3) return clean(node.nodeValue).trim();
        if (node.nodeType !== 1) return '';
        const tag = node.tagName;
        if (/^H[1-6]$/.test(tag)) {
          const text = inline(node).replace(/\s*\n\s*/g, ' ').trim();
          return text ? '#'.repeat(Number(tag[1])) + ' ' + text : '';
        }
        switch (tag) {
          // 段落の中にリストなどが入れ子になることがある（ブラウザの編集で）。そのときは中のブロックを順に
          case 'P': return [...node.childNodes].some(isBlock) ? blocks(node) : inline(node).trim();
          case 'DIV': return [...node.childNodes].some(isBlock) ? blocks(node) : inline(node).trim();
          case 'UL': case 'OL': return list(node);
          case 'LI': return list(node);
          case 'BLOCKQUOTE': return blocks(node).split('\n').map((line) => line ? '> ' + line : '>').join('\n');
          case 'PRE': return pre(node);
          case 'HR': return '---';
          case 'TABLE': return table(node);
          default: return node.outerHTML;
        }
      }

      const indent = (text, width) => text.split('\n').map((line) => line ? ' '.repeat(width) + line : line).join('\n');

      function list(node) {
        if (node.tagName === 'LI') return '- ' + blocks(node, '\n');
        const ordered = node.tagName === 'OL';
        let number = ordered ? (parseInt(node.getAttribute('start'), 10) || 1) : 0;
        const loose = !!node.querySelector(':scope > li > p');
        const items = [];
        let lastWidth = 2;
        [...node.childNodes].forEach((child) => {
          if (child.nodeType === 1 && (child.tagName === 'UL' || child.tagName === 'OL')) {
            // 字下げで、項目の外に入れ子のリストが置かれたとき
            const nested = indent(list(child), lastWidth);
            if (items.length) items[items.length - 1] += '\n' + nested; else items.push(nested);
            return;
          }
          if (!(child.nodeType === 1 && child.tagName === 'LI')) {
            const text = child.nodeType === 3 ? clean(child.nodeValue).trim() : block(child);
            if (text) items.push(text);
            return;
          }
          const marker = ordered ? (number++) + '. ' : '- ';
          lastWidth = marker.length;
          const box = child.querySelector(':scope > input[type=checkbox]');
          const check = box ? (box.hasAttribute('checked') ? '[x] ' : '[ ] ') : '';
          const body = blocks(child, loose ? '\n\n' : '\n').replace(/^\s+/, '');
          items.push(marker + check + indent(body, marker.length).slice(marker.length));
        });
        return items.join(loose ? '\n\n' : '\n');
      }

      function pre(node) {
        if (node.classList.contains('md-raw')) return node.innerText.replace(/\n$/, '');
        const code = node.querySelector('code');
        const lang = node.dataset.lang || ((code && code.className.match(/language-(\S+)/)) || [])[1] || '';
        const text = clean(node.innerText).replace(/\n$/, '');
        const fence = text.includes('```') ? '~~~' : '```';
        return fence + lang + '\n' + text + '\n' + fence;
      }

      function table(node) {
        const rows = [...node.rows];
        if (!rows.length) return '';
        const cell = (c) => inline(c).replace(/\s*\n\s*/g, ' ').replace(/\|/g, '\\|').trim();
        const head = [...rows[0].cells];
        const separator = head.map((c) => {
          const align = c.style.textAlign;
          return align === 'center' ? ':---:' : align === 'right' ? '---:' : align === 'left' ? ':---' : '---';
        });
        const line = (cells) => '| ' + cells.join(' | ') + ' |';
        return [line(head.map(cell)), line(separator), ...rows.slice(1).map((r) => line([...r.cells].map(cell)))].join('\n');
      }

      // MARK: 文章全体

      const dirty = new Set();
      const original = model.head + model.blocks.map((b) => b.source + b.separator).join('') + model.tail;

      function serialize() {
        const parts = [];
        const seen = new Set();
        root.childNodes.forEach((node) => {
          if (node.nodeType === 1 && node.classList.contains('md-front')) return;
          if (node.nodeType === 1 && node.classList.contains('md-block')) {
            const index = Number(node.dataset.i);
            const copy = seen.has(index);
            seen.add(index);
            const text = (dirty.has(node) || copy || !model.blocks[index]) ? blocks(node) : model.blocks[index].source;
            if (text.trim()) parts.push({ text, index: copy ? null : index });
            return;
          }
          const text = node.nodeType === 3 ? clean(node.nodeValue).trim() : block(node);
          if (text.trim()) parts.push({ text, index: null });
        });
        let out = model.head;
        parts.forEach((part, k) => {
          if (k > 0) {
            const previous = parts[k - 1];
            out += (previous.index !== null && part.index === previous.index + 1) ? model.blocks[previous.index].separator : '\n\n';
          } else if (out.trim() && !out.endsWith('\n\n')) {
            out = out.replace(/\n*$/, '\n\n');
          }
          out += part.text;
        });
        if (parts.length) out += model.blocks.length ? model.tail : '\n';
        return out;
      }

      let timer = null;
      let lastSent = original;
      function save() {
        clearTimeout(timer);
        timer = null;
        const text = serialize();
        if (text === lastSent) return;
        lastSent = text;
        post({ type: 'save', text });
      }
      const scheduleSave = () => { clearTimeout(timer); timer = setTimeout(save, 400); };
      window.__macornEditorFlush = save;
      window.__macornEditorSerialize = serialize;
      window.addEventListener('pagehide', save);
      root.addEventListener('focusout', save);

      const updateEmpty = () => root.classList.toggle('md-empty', !clean(root.innerText).trim() && !root.querySelector('img, hr, table'));
      updateEmpty();

      new MutationObserver((records) => {
        for (const record of records) {
          const target = record.target.nodeType === 1 ? record.target : record.target.parentElement;
          const owner = target && target.closest('.md-block');
          if (owner) dirty.add(owner);
          record.addedNodes.forEach((n) => { if (n.nodeType === 1 && n.classList.contains('md-block')) dirty.add(n); });
        }
        updateEmpty();
        scheduleSave();
      }).observe(root, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['checked'] });

      // MARK: Markdown の書き方で変える

      const selection = () => window.getSelection();
      // 全角で打った記号も、Markdown の記号として扱う
      const norm = (text) => text.replace(/＃/g, '#').replace(/＞/g, '>').replace(/[－−]/g, '-').replace(/＊/g, '*')
        .replace(/＋/g, '+').replace(/［/g, '[').replace(/］/g, ']').replace(/｀/g, '`').replace(/　/g, ' ');

      function caretBlock() {
        const s = selection();
        if (!s.rangeCount) return null;
        let node = s.anchorNode;
        if (node && node.nodeType === 3) node = node.parentElement;
        while (node && node !== root) {
          if (/^(P|DIV|H[1-6]|LI|PRE|TD|TH)$/.test(node.tagName)) return node;
          node = node.parentElement;
        }
        return null;
      }
      function textBefore(el) {
        const s = selection();
        const range = document.createRange();
        range.selectNodeContents(el);
        range.setEnd(s.anchorNode, s.anchorOffset);
        return clean(range.toString());
      }
      function textAfter(el) {
        const s = selection();
        const range = document.createRange();
        range.selectNodeContents(el);
        range.setStart(s.focusNode, s.focusOffset);
        return clean(range.toString());
      }
      const atStart = (el) => textBefore(el) === '';
      const atEnd = (el) => textAfter(el).replace(/\n$/, '') === '';
      function placeCaret(node, offset = 0) {
        const range = document.createRange();
        range.setStart(node, offset);
        range.collapse(true);
        selection().removeAllRanges();
        selection().addRange(range);
      }
      // 行の頭からカーソルまでを消す（記号を消して、見た目だけを変えるため）
      function deleteBefore(el) {
        const s = selection();
        const range = document.createRange();
        range.selectNodeContents(el);
        range.setEnd(s.anchorNode, s.anchorOffset);
        s.removeAllRanges();
        s.addRange(range);
        document.execCommand('delete');
      }
      function paragraphAfter(el) {
        const p = document.createElement('p');
        p.appendChild(document.createElement('br'));
        el.after(p);
        placeCaret(p, 0);
      }
      function makeTask(checked) {
        const item = caretBlock() && caretBlock().closest('li');
        if (!item) return;
        item.classList.add('task');
        const box = document.createElement('input');
        box.type = 'checkbox';
        if (checked) box.setAttribute('checked', '');
        item.insertBefore(box, item.firstChild);
        const space = document.createTextNode(' ');
        box.after(space);
        placeCaret(space, 1);
      }

      // 行の頭で「# 」「- 」「1. 」「> 」「[] 」を打ったとき
      function blockShortcut() {
        const s = selection();
        if (!s.isCollapsed) return false;
        const el = caretBlock();
        if (!el) return false;
        const m = norm(textBefore(el)).match(/^(#{1,6}|[-*+](?: \[[ xX]?\])?|\d{1,9}[.)]|>|\[[ xX]?\]) $/);
        if (!m) return false;
        const mark = m[1];
        const tag = el.tagName;
        const task = mark.match(/\[([ xX]?)\]$/);
        if (tag === 'LI') {
          if (!task || el.classList.contains('task')) return false;
          deleteBefore(el);
          makeTask(/x/i.test(task[1]));
          return true;
        }
        if (/^H[1-6]$/.test(tag)) {
          if (!mark.startsWith('#')) return false;
        } else if (tag !== 'P' && tag !== 'DIV') {
          return false;
        }
        deleteBefore(el);
        if (mark.startsWith('#')) {
          document.execCommand('formatBlock', false, 'h' + mark.length);
        } else if (mark === '>') {
          document.execCommand('formatBlock', false, 'blockquote');
        } else if (/^\d/.test(mark)) {
          document.execCommand('insertOrderedList');
          const start = parseInt(mark, 10);
          const list = caretBlock() && caretBlock().closest('ol');
          if (list && start !== 1) list.setAttribute('start', String(start));
        } else {
          document.execCommand('insertUnorderedList');
          if (task) makeTask(/x/i.test(task[1]));
        }
        return true;
      }

      // `**太字**` `*斜体*` `~~打ち消し~~` `` `コード` `` `[文字](URL)` `![説明](画像)` を閉じたとき
      const INLINE = [
        { re: /!\[([^\]]*)\]\(([^)\s]+)\)$/, html: (m) => '<img src="' + attr(m[2]) + '" alt="' + attr(m[1]) + '">' },
        { re: /\[([^\]]+)\]\(([^)\s]+)\)$/, html: (m) => '<a href="' + attr(m[2]) + '">' + esc(m[1]) + '</a>' },
        { re: /(\*\*|__)([^*_\s](?:[^*_]*[^*_\s])?)\1$/, html: (m) => '<strong>' + esc(m[2]) + '</strong>' },
        { re: /(?:^|[^*\w])(\*|_)([^*_\s](?:[^*_]*[^*_\s])?)\1$/, html: (m) => '<em>' + esc(m[2]) + '</em>',
          length: (m) => m[1].length * 2 + m[2].length },
        { re: /~~([^~\s](?:[^~]*[^~\s])?)~~$/, html: (m) => '<del>' + esc(m[1]) + '</del>' },
        { re: /`([^`]+)`$/, html: (m) => '<code>' + esc(m[1]) + '</code>' },
      ];
      const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      const attr = (t) => esc(t).replace(/"/g, '&quot;');

      function inlineShortcut() {
        const s = selection();
        if (!s.isCollapsed) return;
        const node = s.anchorNode;
        if (!node || node.nodeType !== 3 || !node.parentElement || node.parentElement.closest('code, pre, a')) return;
        const offset = s.anchorOffset;
        const text = norm(node.nodeValue.slice(0, offset));
        for (const rule of INLINE) {
          const m = text.match(rule.re);
          if (!m) continue;
          const length = rule.length ? rule.length(m) : m[0].length;
          const range = document.createRange();
          range.setStart(node, offset - length);
          range.setEnd(node, offset);
          s.removeAllRanges();
          s.addRange(range);
          // 後ろに幅のない文字を置いて、続けて打つ文字が強調の外に出るようにする
          document.execCommand('insertHTML', false, rule.html(m) + '​');
          return;
        }
      }

      root.addEventListener('input', (event) => {
        if (event.isComposing) return;
        if (blockShortcut()) return;
        if (/^insert(Text|FromComposition|ReplacementText)$/.test(event.inputType)) inlineShortcut();
      });

      root.addEventListener('keydown', (event) => {
        if (event.isComposing || event.keyCode === 229) return;
        const el = caretBlock();
        if (event.key === 'Enter' && !event.shiftKey && el) {
          const text = norm(clean(el.textContent)).trim();
          if (el.tagName === 'PRE') {
            event.preventDefault();
            // 最後の空の行で Enter（または ⌘Enter）を押すと、コードブロックを抜ける
            if (event.metaKey || (atEnd(el) && /\n\n$|^\n?$/.test(el.innerText.replace(/​/g, '')))) {
              if (!event.metaKey) document.execCommand('delete');
              paragraphAfter(el);
            } else {
              document.execCommand('insertLineBreak');
            }
            return;
          }
          const fence = text.match(/^(```|~~~)(\S*)$/);
          if (fence && (el.tagName === 'P' || el.tagName === 'DIV')) {
            event.preventDefault();
            deleteBefore(el);
            document.execCommand('formatBlock', false, 'pre');
            const block = caretBlock();
            if (block && block.tagName === 'PRE' && fence[2]) block.dataset.lang = fence[2];
            return;
          }
          if (/^(-{3,}|\*{3,}|_{3,})$/.test(text) && (el.tagName === 'P' || el.tagName === 'DIV')) {
            event.preventDefault();
            const rule = document.createElement('hr');
            el.replaceWith(rule);
            paragraphAfter(rule);
            return;
          }
          if (/^H[1-6]$/.test(el.tagName) && atEnd(el)) {
            event.preventDefault();
            paragraphAfter(el);
            return;
          }
          // 空の項目で Enter を押すと、リストを抜ける（入れ子なら1段上がる）
          const item = el.closest('li');
          if (item && !text && !item.querySelector('ul, ol, img')) {
            event.preventDefault();
            const list = item.parentElement;
            if (item === list.lastElementChild && !list.parentElement.closest('li')) {
              item.remove();
              paragraphAfter(list);
              if (!list.querySelector('li')) list.remove();
            } else {
              document.execCommand('outdent');
            }
            return;
          }
        }
        if (event.key === 'Backspace' && selection().isCollapsed && el && atStart(el)) {
          // 行の頭で ⌫ を押すと、見出し・コード・引用・チェックをふつうの段落に戻す（Notion と同じ）
          if (/^H[1-6]$/.test(el.tagName) || el.tagName === 'PRE') {
            event.preventDefault();
            document.execCommand('formatBlock', false, 'p');
            return;
          }
          const quote = el.closest('blockquote');
          if (quote && el.tagName === 'P' && quote.firstElementChild === el) {
            event.preventDefault();
            document.execCommand('outdent');
            return;
          }
          const item = el.closest('li.task');
          if (item) {
            const box = item.querySelector(':scope > input[type=checkbox]');
            if (box) {
              event.preventDefault();
              box.remove();
              item.classList.remove('task');
              return;
            }
          }
        }
        if (event.key === 'Tab') {
          event.preventDefault();
          if (el && el.closest('li')) document.execCommand(event.shiftKey ? 'outdent' : 'indent');
          else if (el && el.tagName === 'PRE') document.execCommand('insertText', false, '    ');
          return;
        }
        if (event.metaKey && !event.shiftKey && !event.altKey && !event.ctrlKey && (event.key === 'b' || event.key === 'i')) {
          event.preventDefault();
          document.execCommand(event.key === 'b' ? 'bold' : 'italic');
        }
      });

      // 貼り付けは文字だけにする（ほかのアプリの見た目を持ち込まない）
      root.addEventListener('paste', (event) => {
        const text = event.clipboardData && event.clipboardData.getData('text/plain');
        if (!text) return;
        event.preventDefault();
        document.execCommand('insertText', false, text);
      });

      root.addEventListener('click', (event) => {
        const target = event.target;
        if (!(target instanceof Element)) return;
        const box = target.closest('li.task > input[type=checkbox]');
        if (box) {
          event.preventDefault();
          const checked = !box.hasAttribute('checked');
          setTimeout(() => { box.toggleAttribute('checked', checked); box.checked = checked; }, 0);
          return;
        }
        // リンクは ⌘ を押しながらクリックで開く（ふつうのクリックは文字の編集）
        const link = target.closest('a[href]');
        if (link && event.metaKey) {
          event.preventDefault();
          const href = link.getAttribute('href');
          if (href.startsWith('#')) {
            const heading = document.getElementById(decodeURIComponent(href.slice(1)));
            if (heading) heading.scrollIntoView();
          } else {
            post({ type: 'open', href: link.href });
          }
        }
      });
      root.addEventListener('mouseover', (event) => {
        const link = event.target instanceof Element && event.target.closest('a[href]');
        if (link && !link.title) link.title = link.getAttribute('href') + '（⌘クリックで開く）';
      });

      // HTML のまま書かれた部分は、ダブルクリックで元の文章を直す
      root.addEventListener('dblclick', (event) => {
        const block = event.target instanceof Element && event.target.closest('.md-block[data-raw]');
        if (!block || block.dataset.editing) return;
        const source = (model.blocks[Number(block.dataset.i)] || {}).source || '';
        block.dataset.editing = '1';
        block.removeAttribute('contenteditable');
        block.removeAttribute('title');
        const raw = document.createElement('pre');
        raw.className = 'md-raw';
        raw.textContent = source;
        block.replaceChildren(raw);
        placeCaret(raw.firstChild || raw, 0);
      });
    })();
    """#
}

/// プレビューの Web の領域。Markdown を編集している間は、ファイル操作に割り当てたキー（⌘⌫・⌘D など）を
/// メニューより先に受け取り、文字の編集に使う（編集中に、選んでいるファイルをゴミ箱に入れたりしないように）
final class PreviewWebView: WKWebView {
    var claimsEditingKeys = false

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if claimsEditingKeys, Self.isEditingKey(event),
           let responder = window?.firstResponder as? NSView, responder === self || responder.isDescendant(of: self) {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// 文字の編集で使うのに、メニューではファイル操作に割り当てているキー
    static func isEditingKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let delete = key == "\u{7f}" || key == "\u{8}"
        switch flags {
        case [.command]: return delete || ["d", "y", "o", "i", "b"].contains(key)
        case [.command, .option]: return delete || key == "v"
        case []: return [NSF5FunctionKey, NSF6FunctionKey].compactMap { UnicodeScalar($0).map { String(Character($0)) } }.contains(key)
        default: return false
        }
    }
}
