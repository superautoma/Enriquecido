import json
import sqlite3
from pathlib import Path

from kivy.app import App
from kivy.clock import Clock
from kivy.graphics import Color, Rectangle, RoundedRectangle, Line
from kivy.metrics import dp
from kivy.properties import StringProperty
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.popup import Popup
from kivy.uix.textinput import TextInput
from kivy.utils import platform


BG = (1, 1, 1, 1)
HEADER_BG = (0.92, 0.96, 1, 1)
TEXT = (0.12, 0.13, 0.15, 1)
MUTED = (0.38, 0.40, 0.43, 1)
BLUE = (0.08, 0.53, 0.86, 1)
LINE = (0.40, 0.42, 0.45, 1)


def html_to_kivy_markup(value):
    import re
    from html import unescape

    value = value or ""
    if not value.strip():
        return "[color=888888]Sin descripción[/color]"

    s = value
    s = re.sub(r"<\s*br\s*/?\s*>", "\n", s, flags=re.I)
    s = re.sub(r"<\s*/\s*(p|div|h[1-6])\s*>", "\n", s, flags=re.I)
    s = re.sub(r"<\s*(p|div|h[1-6])[^>]*>", "", s, flags=re.I)
    s = re.sub(r"<\s*li[^>]*>", "• ", s, flags=re.I)
    s = re.sub(r"<\s*/\s*li\s*>", "\n", s, flags=re.I)
    s = re.sub(r"<\s*/?\s*(ul|ol)[^>]*>", "", s, flags=re.I)

    replacements = [
        (r"<\s*(b|strong)\s*>", "[b]"),
        (r"<\s*/\s*(b|strong)\s*>", "[/b]"),
        (r"<\s*(i|em)\s*>", "[i]"),
        (r"<\s*/\s*(i|em)\s*>", "[/i]"),
        (r"<\s*u\s*>", "[u]"),
        (r"<\s*/\s*u\s*>", "[/u]"),
        (r"<\s*(s|strike)\s*>", "[s]"),
        (r"<\s*/\s*(s|strike)\s*>", "[/s]"),
    ]
    for pattern, repl in replacements:
        s = re.sub(pattern, repl, s, flags=re.I)

    s = re.sub(r"<[^>]+>", "", s)
    return unescape(s).strip() or "[color=888888]Sin descripción[/color]"


class Database:
    def __init__(self, path):
        self.path = Path(path)
        self.init_db()

    def connect(self):
        con = sqlite3.connect(self.path)
        con.row_factory = sqlite3.Row
        return con

    def init_db(self):
        with self.connect() as con:
            con.execute(
                '''
                CREATE TABLE IF NOT EXISTS demo_article (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    name TEXT NOT NULL DEFAULT '',
                    description_html TEXT NOT NULL DEFAULT ''
                )
                '''
            )
            con.execute(
                '''
                INSERT OR IGNORE INTO demo_article(id, name, description_html)
                VALUES (1, '', '')
                '''
            )

    def load(self):
        with self.connect() as con:
            return con.execute(
                "SELECT * FROM demo_article WHERE id = 1"
            ).fetchone()

    def save(self, name, html):
        with self.connect() as con:
            con.execute(
                '''
                UPDATE demo_article
                SET name = ?, description_html = ?
                WHERE id = 1
                ''',
                (name, html),
            )


class UnderlineTextInput(TextInput):
    def __init__(self, **kwargs):
        super().__init__(
            multiline=False,
            background_normal="",
            background_active="",
            background_color=(0, 0, 0, 0),
            foreground_color=TEXT,
            cursor_color=BLUE,
            font_size=dp(20),
            padding=(0, dp(4), 0, dp(4)),
            size_hint_y=None,
            height=dp(46),
            **kwargs
        )
        with self.canvas.after:
            self._line_color = Color(*LINE)
            self._line = Rectangle(pos=(self.x, self.y), size=(self.width, dp(1.4)))
        self.bind(pos=self._sync_line, size=self._sync_line, focus=self._focus_line)

    def _sync_line(self, *_):
        self._line.pos = (self.x, self.y)
        self._line.size = (self.width, dp(1.4 if not self.focus else 2.0))

    def _focus_line(self, *_):
        self._line_color.rgba = BLUE if self.focus else LINE
        self._sync_line()


class LightButton(Button):
    def __init__(self, **kwargs):
        super().__init__(
            background_normal="",
            background_down="",
            background_color=(0, 0, 0, 0),
            color=BLUE,
            font_size=dp(16),
            **kwargs
        )


class FilledButton(Button):
    def __init__(self, text="Guardar", **kwargs):
        super().__init__(
            text=text,
            background_normal="",
            background_down="",
            background_color=(0, 0, 0, 0),
            color=(1, 1, 1, 1),
            font_size=dp(18),
            size_hint_y=None,
            height=dp(54),
            **kwargs
        )
        with self.canvas.before:
            self._bg_color = Color(*BLUE)
            self._bg = RoundedRectangle(pos=self.pos, size=self.size, radius=[dp(12)])
        self.bind(
            pos=lambda *_: setattr(self._bg, "pos", self.pos),
            size=lambda *_: setattr(self._bg, "size", self.size),
        )


class RichPreview(BoxLayout):
    html_value = StringProperty("")

    def __init__(self, on_edit, **kwargs):
        super().__init__(
            orientation="vertical",
            size_hint_y=None,
            height=dp(210),
            spacing=dp(5),
            **kwargs
        )
        self.on_edit = on_edit

        top = BoxLayout(size_hint_y=None, height=dp(30))
        title = Label(
            text="Descripción",
            color=MUTED,
            font_size=dp(16),
            halign="left",
            valign="middle",
        )
        title.bind(size=lambda w, *_: setattr(w, "text_size", w.size))

        edit = LightButton(
            text="Editar formato",
            size_hint=(None, 1),
            width=dp(120),
        )
        edit.bind(on_release=lambda *_: self.on_edit())

        top.add_widget(title)
        top.add_widget(edit)
        self.add_widget(top)

        self.preview_box = BoxLayout(
            size_hint_y=None,
            height=dp(170),
            padding=dp(12),
        )
        with self.preview_box.canvas.before:
            Color(0.995, 0.998, 1, 1)
            self._bg = RoundedRectangle(
                pos=self.preview_box.pos,
                size=self.preview_box.size,
                radius=[dp(10)],
            )
        with self.preview_box.canvas.after:
            Color(0.78, 0.80, 0.83, 1)
            self._border = Line(
                rounded_rectangle=(
                    self.preview_box.x,
                    self.preview_box.y,
                    self.preview_box.width,
                    self.preview_box.height,
                    dp(10),
                ),
                width=1.0,
            )

        def sync(*_):
            self._bg.pos = self.preview_box.pos
            self._bg.size = self.preview_box.size
            self._border.rounded_rectangle = (
                self.preview_box.x,
                self.preview_box.y,
                self.preview_box.width,
                self.preview_box.height,
                dp(10),
            )

        self.preview_box.bind(pos=sync, size=sync)

        self.label = Label(
            text="",
            markup=True,
            color=TEXT,
            font_size=dp(17),
            halign="left",
            valign="top",
        )
        self.label.bind(size=lambda w, *_: setattr(w, "text_size", w.size))
        self.preview_box.add_widget(self.label)
        self.add_widget(self.preview_box)

        self.bind(html_value=lambda *_: self.refresh())
        self.refresh()

    def refresh(self):
        self.label.text = html_to_kivy_markup(self.html_value)



# Android helpers: patrón recomendado por python-for-android/Kivy.
if platform == "android":
    try:
        from jnius import autoclass, cast, PythonJavaClass, java_method
        from android.runnable import run_on_ui_thread

        _PythonActivity = autoclass("org.kivy.android.PythonActivity")
        _WebView = autoclass("android.webkit.WebView")
        _WebViewClient = autoclass("android.webkit.WebViewClient")
        _Dialog = autoclass("android.app.Dialog")
        _LinearLayout = autoclass("android.widget.LinearLayout")
        _AndroidButton = autoclass("android.widget.Button")
        _VGParams = autoclass("android.view.ViewGroup$LayoutParams")
        _LLParams = autoclass("android.widget.LinearLayout$LayoutParams")
        _Window = autoclass("android.view.Window")
        _AndroidColor = autoclass("android.graphics.Color")

        ANDROID_WEBVIEW_READY = True
    except Exception:
        ANDROID_WEBVIEW_READY = False
else:
    ANDROID_WEBVIEW_READY = False


if platform == "android":
    @run_on_ui_thread
    def _open_editor_on_android_ui(editor_obj):
        editor_obj._show_dialog_ui()


class AndroidRichTextEditor:
    def __init__(self, initial_html, on_saved, on_error=None):
        self.initial_html = initial_html or ""
        self.on_saved = on_saved
        self.on_error = on_error
        self._refs = []
        self.dialog = None
        self.webview = None

    def open(self):
        if platform != "android":
            raise RuntimeError(
                "El editor WebView sólo puede probarse en Android."
            )

        if not ANDROID_WEBVIEW_READY:
            raise RuntimeError(
                "No se pudo cargar PyJNIus/android.runnable."
            )

        try:
            _open_editor_on_android_ui(self)
        except Exception as exc:
            self._report_error(exc)

    def _report_error(self, exc):
        if self.on_error:
            Clock.schedule_once(
                lambda dt, err=exc: self.on_error(err),
                0
            )

    def _editor_html(self):
        import base64

        initial_b64 = base64.b64encode(
            self.initial_html.encode("utf-8")
        ).decode("ascii")

        template = r'''<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
* { box-sizing:border-box; }
html,body {
    margin:0; padding:0; background:#fff; color:#20242a;
    font-family:Arial,sans-serif;
}
.toolbar {
    display:flex; gap:5px; align-items:center; overflow-x:auto;
    white-space:nowrap; padding:8px; background:#f8fafc;
    border-bottom:1px solid #d7dce2;
}
.tb, select, .colorbox {
    height:38px; min-width:42px; border:1px solid #ccd4dc;
    border-radius:8px; background:#fff; color:#20242a;
    font-size:18px; font-weight:700; padding:0 9px;
}
.sep { width:1px; min-width:1px; height:30px; background:#d3d8dd; }
.colorbox {
    display:inline-flex; align-items:center; gap:4px; font-size:14px;
}
input[type=color] { width:28px; height:25px; border:0; padding:0; }
#editor {
    min-height:64vh; padding:14px; outline:none;
    font-size:18px; line-height:1.45; caret-color:#1685d1;
}
#editor:empty:before {
    content:"Escribe aquí la descripción…"; color:#9ca1a8;
}
</style>
</head>
<body>
<div class="toolbar">
    <button class="tb" data-cmd="bold"><b>B</b></button>
    <button class="tb" data-cmd="italic"><i>I</i></button>
    <button class="tb" data-cmd="underline"><u>U</u></button>
    <button class="tb" data-cmd="strikeThrough"><s>S</s></button>
    <span class="sep"></span>

    <label class="colorbox">A
        <input id="textColor" type="color" value="#222222">
    </label>

    <label class="colorbox">▰
        <input id="bgColor" type="color" value="#fff19c">
    </label>

    <select id="fontSize">
        <option value="14px">Pequeño</option>
        <option value="18px" selected>Normal</option>
        <option value="24px">Grande</option>
        <option value="32px">Muy grande</option>
    </select>

    <span class="sep"></span>

    <button class="tb" data-align="left">☰</button>
    <button class="tb" data-align="center">≡</button>
    <button class="tb" data-align="right">☷</button>

    <span class="sep"></span>

    <button class="tb" data-cmd="insertUnorderedList">• Lista</button>
    <button class="tb" data-cmd="insertOrderedList">1. Lista</button>
    <button class="tb" id="clearFormat">Tx</button>
</div>

<div id="editor" contenteditable="true" spellcheck="true"></div>

<script>
const editor = document.getElementById("editor");
const initialB64 = "__INITIAL_B64__";

function decodeB64(str) {
    try {
        const bytes = atob(str);
        const encoded = Array.from(bytes)
            .map(c => "%" + c.charCodeAt(0).toString(16).padStart(2,"0"))
            .join("");
        return decodeURIComponent(encoded);
    } catch(e) {
        return "";
    }
}

editor.innerHTML = decodeB64(initialB64);

let savedRange = null;

function rememberSelection() {
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) return;

    const range = sel.getRangeAt(0);
    if (editor.contains(range.commonAncestorContainer)) {
        savedRange = range.cloneRange();
    }
}

function restoreSelection() {
    editor.focus();

    if (!savedRange) return;

    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(savedRange);
}

document.addEventListener("selectionchange", rememberSelection);

document.querySelectorAll("[data-cmd]").forEach(btn => {
    btn.addEventListener("mousedown", e => e.preventDefault());

    btn.addEventListener("click", () => {
        restoreSelection();
        document.execCommand(btn.dataset.cmd, false, null);
        rememberSelection();
    });
});

function applyInlineStyle(styles) {
    restoreSelection();

    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) return;

    const range = sel.getRangeAt(0);
    const span = document.createElement("span");

    Object.entries(styles).forEach(([key, value]) => {
        span.style[key] = value;
    });

    if (range.collapsed) {
        const marker = document.createTextNode("\u200B");
        span.appendChild(marker);
        range.insertNode(span);

        const caret = document.createRange();
        caret.setStart(marker, marker.length);
        caret.collapse(true);

        sel.removeAllRanges();
        sel.addRange(caret);
        savedRange = caret.cloneRange();
        return;
    }

    const fragment = range.extractContents();
    span.appendChild(fragment);
    range.insertNode(span);

    const newRange = document.createRange();
    newRange.selectNodeContents(span);

    sel.removeAllRanges();
    sel.addRange(newRange);
    savedRange = newRange.cloneRange();
}

document.getElementById("textColor").addEventListener("change", e => {
    applyInlineStyle({color:e.target.value});
});

document.getElementById("bgColor").addEventListener("change", e => {
    applyInlineStyle({backgroundColor:e.target.value});
});

document.getElementById("fontSize").addEventListener("change", e => {
    applyInlineStyle({fontSize:e.target.value});
});

document.querySelectorAll("[data-align]").forEach(btn => {
    btn.addEventListener("mousedown", e => e.preventDefault());

    btn.addEventListener("click", () => {
        restoreSelection();

        const command =
            btn.dataset.align === "center" ? "justifyCenter" :
            btn.dataset.align === "right" ? "justifyRight" :
            "justifyLeft";

        document.execCommand(command, false, null);
        rememberSelection();
    });
});

document.getElementById("clearFormat")
    .addEventListener("mousedown", e => e.preventDefault());

document.getElementById("clearFormat")
    .addEventListener("click", () => {
        restoreSelection();
        document.execCommand("removeFormat", false, null);
        rememberSelection();
    });

editor.focus();
</script>
</body>
</html>'''

        return template.replace("__INITIAL_B64__", initial_b64)

    def _show_dialog_ui(self):
        try:
            activity = cast(
                "android.app.Activity",
                _PythonActivity.mActivity
            )

            if activity is None:
                raise RuntimeError(
                    "PythonActivity.mActivity es None."
                )

            outer = self

            class ClickListener(PythonJavaClass):
                __javainterfaces__ = [
                    "android/view/View$OnClickListener"
                ]
                __javacontext__ = "app"

                def __init__(self, callback):
                    super().__init__()
                    self.callback = callback

                @java_method("(Landroid/view/View;)V")
                def onClick(self, view):
                    self.callback()

            class ValueCallback(PythonJavaClass):
                __javainterfaces__ = [
                    "android/webkit/ValueCallback"
                ]
                __javacontext__ = "app"

                def __init__(self, callback):
                    super().__init__()
                    self.callback = callback

                @java_method("(Ljava/lang/Object;)V")
                def onReceiveValue(self, value):
                    self.callback(value)

            dialog = _Dialog(activity)
            dialog.requestWindowFeature(_Window.FEATURE_NO_TITLE)

            root = _LinearLayout(activity)
            root.setOrientation(_LinearLayout.VERTICAL)
            root.setBackgroundColor(_AndroidColor.WHITE)

            webview = _WebView(activity)

            settings = webview.getSettings()
            settings.setJavaScriptEnabled(True)
            settings.setDomStorageEnabled(True)
            settings.setLoadWithOverviewMode(True)
            settings.setUseWideViewPort(True)

            webview.setWebViewClient(_WebViewClient())
            webview.setBackgroundColor(_AndroidColor.WHITE)
            webview.setFocusable(True)
            webview.setFocusableInTouchMode(True)

            webview.loadDataWithBaseURL(
                "https://localhost/",
                self._editor_html(),
                "text/html",
                "UTF-8",
                None,
            )

            web_params = _LLParams(
                _VGParams.MATCH_PARENT,
                0,
                1.0,
            )
            root.addView(webview, web_params)

            actions = _LinearLayout(activity)
            actions.setOrientation(_LinearLayout.HORIZONTAL)
            actions.setPadding(10, 8, 10, 8)
            actions.setBackgroundColor(
                _AndroidColor.rgb(248, 250, 252)
            )

            cancel_btn = _AndroidButton(activity)
            cancel_btn.setText("CANCELAR")

            save_btn = _AndroidButton(activity)
            save_btn.setText("GUARDAR")

            action_params = _LLParams(
                0,
                _VGParams.WRAP_CONTENT,
                1.0,
            )

            actions.addView(cancel_btn, action_params)
            actions.addView(save_btn, action_params)

            root.addView(
                actions,
                _LLParams(
                    _VGParams.MATCH_PARENT,
                    _VGParams.WRAP_CONTENT,
                ),
            )

            self.dialog = dialog
            self.webview = webview

            def cancel():
                try:
                    webview.stopLoading()
                    webview.destroy()
                except Exception:
                    pass
                dialog.dismiss()

            def receive(value):
                try:
                    raw = str(value)
                    html = (
                        ""
                        if raw in ("null", "None")
                        else json.loads(raw)
                    )
                except Exception:
                    html = ""

                try:
                    dialog.dismiss()
                    webview.destroy()
                except Exception:
                    pass

                Clock.schedule_once(
                    lambda dt, result=html:
                        outer.on_saved(result),
                    0,
                )

            def save():
                callback = ValueCallback(receive)
                outer._refs.append(callback)

                webview.evaluateJavascript(
                    "document.getElementById('editor').innerHTML",
                    callback,
                )

            cancel_listener = ClickListener(cancel)
            save_listener = ClickListener(save)

            self._refs.extend(
                [cancel_listener, save_listener]
            )

            cancel_btn.setOnClickListener(cancel_listener)
            save_btn.setOnClickListener(save_listener)

            dialog.setContentView(root)
            dialog.show()

            window = dialog.getWindow()
            if window is not None:
                window.setLayout(
                    _VGParams.MATCH_PARENT,
                    _VGParams.MATCH_PARENT,
                )
                window.setSoftInputMode(0x10)

            webview.requestFocus()

        except Exception as exc:
            self._report_error(exc)


class MainView(BoxLayout):
    description_html = StringProperty("")

    def __init__(self, app_ref, **kwargs):
        super().__init__(orientation="vertical", **kwargs)
        self.app_ref = app_ref

        with self.canvas.before:
            Color(*BG)
            self._bg = Rectangle(pos=self.pos, size=self.size)
        self.bind(
            pos=lambda *_: setattr(self._bg, "pos", self.pos),
            size=lambda *_: setattr(self._bg, "size", self.size),
        )

        header = BoxLayout(
            size_hint_y=None,
            height=dp(82),
            padding=(dp(18), 0),
        )
        with header.canvas.before:
            Color(*HEADER_BG)
            self._header_bg = Rectangle(pos=header.pos, size=header.size)
        header.bind(
            pos=lambda *_: setattr(self._header_bg, "pos", header.pos),
            size=lambda *_: setattr(self._header_bg, "size", header.size),
        )

        title = Label(
            text="Prueba editor enriquecido",
            color=TEXT,
            bold=True,
            font_size=dp(25),
            halign="left",
            valign="middle",
        )
        title.bind(size=lambda w, *_: setattr(w, "text_size", w.size))
        header.add_widget(title)
        self.add_widget(header)

        form = BoxLayout(
            orientation="vertical",
            padding=(dp(20), dp(22)),
            spacing=dp(12),
        )

        name_label = Label(
            text="Nombre*",
            color=MUTED,
            font_size=dp(16),
            halign="left",
            valign="middle",
            size_hint_y=None,
            height=dp(24),
        )
        name_label.bind(size=lambda w, *_: setattr(w, "text_size", w.size))
        form.add_widget(name_label)

        self.name_input = UnderlineTextInput()
        form.add_widget(self.name_input)

        self.rich = RichPreview(on_edit=self.open_rich_editor)
        form.add_widget(self.rich)

        save = FilledButton(text="Guardar artículo")
        save.bind(on_release=lambda *_: self.save_article())
        form.add_widget(save)

        self.status = Label(
            text="",
            color=MUTED,
            font_size=dp(14),
            size_hint_y=None,
            height=dp(30),
        )
        form.add_widget(self.status)

        self.add_widget(form)
        self.load_data()

    def load_data(self):
        row = self.app_ref.db.load()
        self.name_input.text = row["name"] or ""
        self.description_html = row["description_html"] or ""
        self.rich.html_value = self.description_html

    def open_rich_editor(self):
        try:
            editor = AndroidRichTextEditor(
                self.description_html,
                on_saved=self.on_rich_saved,
                on_error=self.on_rich_error,
            )
            self.app_ref.rich_editor = editor
            editor.open()
        except Exception as exc:
            self.on_rich_error(exc)

    def on_rich_saved(self, html):
        self.description_html = html or ""
        self.rich.html_value = self.description_html
        self.status.text = "Descripción actualizada. Pulsa «Guardar artículo»."

    def on_rich_error(self, exc):
        message = str(exc).strip()

        first_lines = [
            line.strip()
            for line in message.splitlines()
            if line.strip()
        ][:6]

        short_message = "\n".join(first_lines) or repr(exc)

        try:
            log_path = Path(
                self.app_ref.user_data_dir
            ) / "richtext_error.txt"

            log_path.write_text(
                message,
                encoding="utf-8"
            )

            short_message += (
                "\n\nInforme completo:\n"
                + str(log_path)
            )
        except Exception:
            pass

        self.app_ref.show_message(
            "Editor no disponible",
            short_message
        )

    def save_article(self):
        name = self.name_input.text.strip()
        if not name:
            self.app_ref.show_message(
                "Falta el nombre",
                "Escribe un nombre antes de guardar.",
            )
            return

        self.app_ref.db.save(name, self.description_html)
        self.status.text = "Guardado correctamente en SQLite."


class RichTextTestApp(App):
    def build(self):
        self.title = "Prueba Rich Text"
        db_path = Path(self.user_data_dir) / "richtext_test.db"
        self.db = Database(db_path)
        self.rich_editor = None
        return MainView(self)

    def show_message(self, title, message):
        content = BoxLayout(
            orientation="vertical",
            padding=dp(14),
            spacing=dp(10),
        )
        label = Label(
            text=message,
            color=TEXT,
            halign="left",
            valign="middle",
        )
        label.bind(size=lambda w, *_: setattr(w, "text_size", w.size))

        close = FilledButton(text="Aceptar")
        popup = Popup(
            title=title,
            content=content,
            size_hint=(0.88, 0.42),
        )
        close.bind(on_release=lambda *_: popup.dismiss())
        content.add_widget(label)
        content.add_widget(close)
        popup.open()


if __name__ == "__main__":
    RichTextTestApp().run()
