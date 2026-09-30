// =====================================================================
// Controls.cs - Biblioteca de controles visuais do TI Suite
// Compilada pelo CodeDom do Windows PowerShell 5.1 => somente C# 5
// (sem $"", sem ?., sem nameof, sem expression-bodied members).
// O dev\Build-Release.ps1 gera bin\TISuite.Controls.dll a partir deste
// arquivo; sem a DLL, o 00-Controls.ps1 compila na hora (mais lento).
// =====================================================================
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace TISuite
{
    // ---------------------------------------------------------------
    // Paleta unica de cores (fonte da verdade; o 01-Theme.ps1 le daqui)
    // ---------------------------------------------------------------
    public static class Pal
    {
        public static readonly Color Bg          = Color.FromArgb(15, 23, 42);
        public static readonly Color BgDeep      = Color.FromArgb(11, 17, 32);
        public static readonly Color Card        = Color.FromArgb(30, 41, 59);
        public static readonly Color CardAlt     = Color.FromArgb(23, 32, 51);
        public static readonly Color Sidebar     = Color.FromArgb(17, 26, 46);
        public static readonly Color Border      = Color.FromArgb(51, 65, 85);
        public static readonly Color BorderSoft  = Color.FromArgb(38, 54, 77);
        public static readonly Color Primary     = Color.FromArgb(56, 189, 248);
        public static readonly Color PrimaryDeep = Color.FromArgb(14, 165, 233);
        public static readonly Color Danger      = Color.FromArgb(244, 63, 94);
        public static readonly Color DangerDeep  = Color.FromArgb(190, 18, 60);
        public static readonly Color Success     = Color.FromArgb(16, 185, 129);
        public static readonly Color Warning     = Color.FromArgb(245, 158, 11);
        public static readonly Color TextMain    = Color.FromArgb(248, 250, 252);
        public static readonly Color TextMuted   = Color.FromArgb(148, 163, 184);
        public static readonly Color TextDim     = Color.FromArgb(100, 116, 139);
        public static readonly Color ConsoleBg   = Color.FromArgb(2, 6, 23);
        public static readonly Color Hover       = Color.FromArgb(36, 52, 77);
        public static readonly Color ActiveRow   = Color.FromArgb(30, 48, 74);
        public static readonly Color OnPrimary   = Color.FromArgb(8, 20, 36);
    }

    // ---------------------------------------------------------------
    // Utilitarios de desenho
    // ---------------------------------------------------------------
    public static class Gfx
    {
        public static GraphicsPath RoundRect(float x, float y, float w, float h, float r)
        {
            GraphicsPath p = new GraphicsPath();
            float d = Math.Min(r * 2f, Math.Min(w, h));
            if (d < 2f) { p.AddRectangle(new RectangleF(x, y, w, h)); p.CloseFigure(); return p; }
            p.AddArc(new RectangleF(x, y, d, d), 180, 90);
            p.AddArc(new RectangleF(x + w - d, y, d, d), 270, 90);
            p.AddArc(new RectangleF(x + w - d, y + h - d, d, d), 0, 90);
            p.AddArc(new RectangleF(x, y + h - d, d, d), 90, 90);
            p.CloseFigure();
            return p;
        }

        public static void Prep(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        }

        // Pinta o fundo completo do controle com a cor efetiva do container.
        // Controles derivados de ButtonBase nao pintam fundo (OnPaintBackground
        // e' omitido) e deixam pixel transparente: o buffer reciclado do WinForms
        // carrega conteudo de outros controles = "fantasmas" na tela.
        public static void PaintBg(Control c, Graphics g)
        {
            if (c == null) return;
            Color bg = Pal.Bg;
            Control p = c.Parent;
            while (p != null)
            {
                if (p.BackColor.ToArgb() == Color.Transparent.ToArgb()) { p = p.Parent; continue; }
                if (p is RoundPanel) bg = ((RoundPanel)p).FillColor;
                else bg = p.BackColor;
                break;
            }
            using (SolidBrush b = new SolidBrush(bg)) g.FillRectangle(b, 0, 0, c.Width, c.Height);
        }

        public static Color Lerp(Color a, Color b, float t)
        {
            if (t < 0f) t = 0f;
            if (t > 1f) t = 1f;
            return Color.FromArgb(
                (int)(a.A + (b.A - a.A) * t),
                (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t),
                (int)(a.B + (b.B - a.B) * t));
        }

        public static void FillRound(Graphics g, RectangleF r, float radius, Color fill, Color border, int borderW)
        {
            using (GraphicsPath path = RoundRect(r.X, r.Y, r.Width, r.Height, radius))
            {
                if (fill.A > 0)
                {
                    using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, path);
                    if (r.Height >= 20f && r.Width >= 20f && fill.A > 150)
                    {
                        float h = Math.Min(r.Height * 0.45f, 26f);
                        RectangleF glassRect = new RectangleF(r.X + 1f, r.Y + 1f, r.Width - 2f, h);
                        using (GraphicsPath topPath = RoundRect(glassRect.X, glassRect.Y, glassRect.Width, glassRect.Height, radius - 1f))
                        {
                            using (LinearGradientBrush glass = new LinearGradientBrush(
                                glassRect,
                                Color.FromArgb(20, 255, 255, 255),
                                Color.FromArgb(0, 255, 255, 255),
                                LinearGradientMode.Vertical))
                            {
                                g.FillPath(glass, topPath);
                            }
                        }
                    }
                }
                if (borderW > 0 && border.A > 0)
                {
                    using (Pen p = new Pen(border, borderW)) { p.Alignment = PenAlignment.Inset; g.DrawPath(p, path); }
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Interop: DPI, janela, arrasto, backdrop escuro, tema das barras
    // ---------------------------------------------------------------
    public static class Native
    {
        [DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool ReleaseCapture();
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
        [DllImport("shcore.dll")] private static extern int SetProcessDpiAwareness(int awareness);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] private static extern int SetWindowThemeNative(IntPtr hWnd, string pszSubAppName, string pszSubIdList);

        public static void EnableDpi()
        {
            try { SetProcessDpiAwarenessContext(new IntPtr(-4)); return; } catch { }
            try { if (SetProcessDpiAwareness(2) == 0) return; } catch { }
            try { SetProcessDPIAware(); } catch { }
        }

        public static void DragWindow(Control c)
        {
            ReleaseCapture();
            SendMessage(c.Handle, 0xA1, (IntPtr)0x2, IntPtr.Zero);
        }

        public static bool RoundWindow(Form f)
        {
            int hr = -1;
            try { int v = 2; hr = DwmSetWindowAttribute(f.Handle, 33, ref v, 4); } catch { hr = -1; }
            if (hr != 0) { try { int v = 1; hr = DwmSetWindowAttribute(f.Handle, 33, ref v, 4); } catch { hr = -1; } }
            try { int dark = 1; DwmSetWindowAttribute(f.Handle, 20, ref dark, 4); } catch { }
            return hr == 0;
        }

        public static void ApplyRegion(Form f, int radius)
        {
            if (f.WindowState == FormWindowState.Maximized) { f.Region = null; return; }
            using (GraphicsPath p = Gfx.RoundRect(0, 0, f.Width, f.Height, radius))
            {
                Region old = f.Region;
                f.Region = new Region(p);
                if (old != null) old.Dispose();
            }
        }

        // Tema escuro nas barras de rolagem nativas (Windows 10 1809+). Melhor esforco.
        public static int SetWindowTheme(IntPtr hWnd, string subApp, string subIdList)
        {
            try { return SetWindowThemeNative(hWnd, subApp, subIdList); } catch { return -1; }
        }

        public static void NoOp() { }

        public static void ShowNoActivate(Form f)
        {
            IntPtr h = f.Handle;
            ShowWindow(h, 8); // SW_SHOWNA
        }
    }

    // ---------------------------------------------------------------
    // TIScrollFlow - FlowLayoutPanel que esconde a barra de rolagem
    // nativa (tema claro do sistema) mantendo a rolagem (wheel) ativa.
    // ---------------------------------------------------------------
    public class TIScrollFlow : FlowLayoutPanel
    {
        [DllImport("user32.dll")]
        private static extern bool EnumChildWindows(IntPtr hWnd, EnumChildProc cb, IntPtr lParam);
        private delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        private Timer _sbTimer;

        private void HideBars()
        {
            if (!IsHandleCreated) return;
            const uint flags = 0x0002 | 0x0001 | 0x0004 | 0x0010 | 0x0080; // NOMOVE|NOSIZE|NOZORDER|NOACTIVATE|HIDEWINDOW
            EnumChildWindows(Handle, delegate(IntPtr h, IntPtr l)
            {
                if (IsWindowVisible(h))
                {
                    System.Text.StringBuilder cls = new System.Text.StringBuilder(128);
                    GetClassName(h, cls, 128);
                    if (cls.ToString().IndexOf("SCROLLBAR", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, flags);
                    }
                }
                return true;
            }, IntPtr.Zero);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            if (_sbTimer == null)
            {
                _sbTimer = new Timer();
                _sbTimer.Interval = 120;
                _sbTimer.Tick += delegate(object s, EventArgs ev) { if (Visible) HideBars(); };
                _sbTimer.Start();
            }
        }

        protected override void OnHandleDestroyed(EventArgs e)
        {
            if (_sbTimer != null) { _sbTimer.Stop(); _sbTimer.Dispose(); _sbTimer = null; }
            base.OnHandleDestroyed(e);
        }

        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            HideBars();
        }
    }

    // ---------------------------------------------------------------
    // RoundPanel - painel com cantos arredondados + borda 1px
    // ---------------------------------------------------------------
    public class RoundPanel : Panel
    {
        public int Radius = 12;
        public Color FillColor = Pal.Card;
        public Color BorderColor = Pal.Border;
        public int BorderWidth = 1;
        public Color BackdropColor = Pal.Bg;
        public bool PaintBackdrop = true;

        public RoundPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            if (PaintBackdrop) e.Graphics.Clear(BackdropColor);
            else base.OnPaintBackground(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Gfx.Prep(e.Graphics);
            Gfx.FillRound(e.Graphics, new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f),
                          Radius, FillColor, BorderColor, BorderWidth);
            base.OnPaint(e);
        }
    }

    // ---------------------------------------------------------------
    // PremiumButton - botao animado (hover/pressed) com icone opcional
    // ---------------------------------------------------------------
    public class PremiumButton : ButtonBase
    {
        public enum Kind { Primary, Danger, Success, Outline, Ghost, Soft }

        private Kind _style = Kind.Outline;
        private string _glyph = "";
        private float _glyphSize = 13f;
        private int _radius = 9;
        private Color _cur;
        private Color _target;
        private bool _hot;
        private bool _down;
        private Timer _anim;
        private Font _iconFont;

        public int Radius { get { return _radius; } set { _radius = value; Invalidate(); } }
        public float GlyphSize { get { return _glyphSize; } set { _glyphSize = value; RebuildIconFont(); Invalidate(); } }

        public Kind Style
        {
            get { return _style; }
            set { _style = value; if (!_hot) { _cur = BaseColor(); _target = _cur; } Invalidate(); }
        }

        public string Glyph
        {
            get { return _glyph; }
            set { _glyph = value == null ? "" : value; RebuildIconFont(); Invalidate(); }
        }

        public PremiumButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.Selectable, true);
            Cursor = Cursors.Hand;
            UseMnemonic = false;
            Height = 38;
            DoubleBuffered = true;
            Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
            _cur = BaseColor();
            _target = _cur;
        }

        // ButtonBase nao tem PerformClick (so Button). Os dialogos usam Enter = clique.
        public void PerformClick()
        {
            if (Enabled && Visible) OnClick(EventArgs.Empty);
        }

        private void RebuildIconFont()
        {
            if (_iconFont != null) { _iconFont.Dispose(); _iconFont = null; }
            if (_glyphSize > 0f) _iconFont = new Font("Segoe MDL2 Assets", _glyphSize, FontStyle.Regular);
        }

        private Color BaseColor()
        {
            switch (_style)
            {
                case Kind.Primary: return Pal.Primary;
                case Kind.Danger: return Pal.Danger;
                case Kind.Success: return Pal.Success;
                case Kind.Soft: return Pal.CardAlt;
                case Kind.Ghost: return Color.Transparent;
                default: return Pal.Card;
            }
        }

        private Color HotColor()
        {
            switch (_style)
            {
                case Kind.Primary: return Gfx.Lerp(Pal.Primary, Color.White, 0.15f);
                case Kind.Danger: return Gfx.Lerp(Pal.Danger, Color.White, 0.15f);
                case Kind.Success: return Gfx.Lerp(Pal.Success, Color.White, 0.15f);
                case Kind.Ghost: return Pal.Hover;
                case Kind.Soft: return Gfx.Lerp(Pal.CardAlt, Pal.Hover, 0.7f);
                default: return Pal.Hover;
            }
        }

        private Color TextColor()
        {
            switch (_style)
            {
                case Kind.Primary: return Pal.OnPrimary;
                case Kind.Success: return Pal.OnPrimary;
                case Kind.Ghost: return _hot ? Pal.TextMain : Pal.TextMuted;
                default: return Pal.TextMain;
            }
        }

        private Color BorderColor()
        {
            if (_style == Kind.Outline) return _hot ? Pal.Primary : Pal.Border;
            if (_style == Kind.Ghost) return _hot ? Pal.BorderSoft : Color.Transparent;
            if (_style == Kind.Soft) return Pal.BorderSoft;
            return Color.Transparent;
        }

        private void Animate(Color target)
        {
            _target = target;
            if (_anim == null)
            {
                _anim = new Timer();
                _anim.Interval = 16;
                _anim.Tick += OnAnimTick;
            }
            _anim.Start();
        }

        private void OnAnimTick(object sender, EventArgs e)
        {
            _cur = Gfx.Lerp(_cur, _target, 0.4f);
            bool done = Math.Abs(_cur.A - _target.A) <= 1 &&
                        Math.Abs(_cur.R - _target.R) <= 1 &&
                        Math.Abs(_cur.G - _target.G) <= 1 &&
                        Math.Abs(_cur.B - _target.B) <= 1;
            if (done) { _cur = _target; _anim.Stop(); }
            Invalidate();
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            base.OnMouseEnter(e);
            _hot = true;
            if (Enabled) Animate(HotColor());
            Invalidate();
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            _hot = false;
            _down = false;
            if (Enabled) Animate(BaseColor());
            Invalidate();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left) { _down = true; Invalidate(); }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            _down = false;
            Invalidate();
        }

        protected override void OnEnabledChanged(EventArgs e)
        {
            base.OnEnabledChanged(e);
            Cursor = Enabled ? Cursors.Hand : Cursors.Default;
            _cur = Enabled ? (_hot ? HotColor() : BaseColor()) : Pal.CardAlt;
            _target = _cur;
            Invalidate();
        }

        protected override void OnTextChanged(EventArgs e)
        {
            base.OnTextChanged(e);
            Invalidate();
        }

        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Gfx.Prep(g);
            Gfx.PaintBg(this, g);

            Color fill = Enabled ? _cur : Pal.CardAlt;
            Color border = Enabled ? BorderColor() : Pal.BorderSoft;
            Color tc = Enabled ? TextColor() : Pal.TextDim;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f);

            using (GraphicsPath path = Gfx.RoundRect(r.X, r.Y, r.Width, r.Height, _radius))
            {
                if (fill.A > 0)
                {
                    if (Enabled && (_style == Kind.Primary || _style == Kind.Danger || _style == Kind.Success))
                    {
                        Color topC = Gfx.Lerp(fill, Color.White, 0.18f);
                        using (LinearGradientBrush lgb = new LinearGradientBrush(r, topC, fill, LinearGradientMode.Vertical))
                            g.FillPath(lgb, path);

                        using (Pen topPen = new Pen(Color.FromArgb(50, 255, 255, 255), 1f))
                        {
                            using (GraphicsPath innerTop = Gfx.RoundRect(r.X + 1f, r.Y + 1f, r.Width - 2f, r.Height - 2f, _radius - 1f))
                                g.DrawPath(topPen, innerTop);
                        }
                    }
                    else
                    {
                        using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, path);
                    }
                }
                if (_down && Enabled)
                {
                    using (SolidBrush b = new SolidBrush(Color.FromArgb(45, Color.Black))) g.FillPath(b, path);
                }
                if (border.A > 0)
                {
                    using (Pen p = new Pen(border, 1f)) { p.Alignment = PenAlignment.Inset; g.DrawPath(p, path); }
                }
                if (Focused && Enabled && ShowFocusCues)
                {
                    using (Pen p = new Pen(Gfx.Lerp(border, Pal.Primary, 0.85f), 1.5f))
                    {
                        using (GraphicsPath inner = Gfx.RoundRect(r.X + 2f, r.Y + 2f, r.Width - 4f, r.Height - 4f, _radius - 2f))
                            g.DrawPath(p, inner);
                    }
                }
            }

            // Medicao e desenho com o MESMO motor (GDI/TextRenderer): texto centralizado de verdade.
            string txt = Text == null ? "" : Text;
            TextFormatFlags tf = TextFormatFlags.NoPadding | TextFormatFlags.SingleLine;
            float iconW = 0f;
            SizeF gs = SizeF.Empty;
            if (_glyph.Length > 0 && _iconFont != null)
            {
                gs = g.MeasureString(_glyph, _iconFont, PointF.Empty, StringFormat.GenericTypographic);
                iconW = gs.Width + (txt.Length > 0 ? 8f : 0f);
            }
            Size ts = txt.Length > 0 ? TextRenderer.MeasureText(g, txt, Font, new Size(int.MaxValue, int.MaxValue), tf) : Size.Empty;
            float total = iconW + ts.Width;
            float x0 = Math.Max(10f, (Width - total) / 2f);

            if (iconW > 0f)
            {
                using (SolidBrush b = new SolidBrush(tc))
                    g.DrawString(_glyph, _iconFont, b, x0, (Height - gs.Height) / 2f + 0.5f, StringFormat.GenericTypographic);
            }
            if (ts.Width > 0)
            {
                Rectangle tr = new Rectangle((int)(x0 + iconW), 0, Math.Max(4, (int)(Width - x0 - iconW - 6)), Height);
                TextRenderer.DrawText(g, txt, Font, tr, tc,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left | tf | TextFormatFlags.EndEllipsis);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_anim != null) _anim.Dispose();
                if (_iconFont != null) _iconFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }

    // ---------------------------------------------------------------
    // SidebarItem - item de navegacao com barra de acento e atalho
    // ---------------------------------------------------------------
    public class SidebarItem : ButtonBase
    {
        private string _glyph = "";
        private string _label = "";
        private string _hint = "";
        private bool _active;
        private bool _hot;
        private Font _iconFont;
        private Font _hintFont;

        public string Glyph
        {
            get { return _glyph; }
            set { _glyph = value == null ? "" : value; if (_iconFont != null) _iconFont.Dispose(); _iconFont = new Font("Segoe MDL2 Assets", 13f); Invalidate(); }
        }

        public string ItemText
        {
            get { return _label; }
            set { _label = value == null ? "" : value; Invalidate(); }
        }

        // Texto discreto a direita (ex.: "Ctrl+1")
        public string HintText
        {
            get { return _hint; }
            set { _hint = value == null ? "" : value; Invalidate(); }
        }

        public bool Active
        {
            get { return _active; }
            set { _active = value; Invalidate(); }
        }

        public SidebarItem()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.Selectable, true);
            Height = 42;
            Cursor = Cursors.Hand;
            UseMnemonic = false;
            Font = new Font("Segoe UI", 9.5f);
            _hintFont = new Font("Segoe UI", 7.5f);
        }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hot = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hot = false; Invalidate(); }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Gfx.Prep(g);
            Gfx.PaintBg(this, g);

            Color fill = _active ? Pal.ActiveRow : (_hot && Enabled ? Pal.Hover : Color.Transparent);
            RectangleF r = new RectangleF(6f, 4f, Width - 12f, Height - 8f);
            Gfx.FillRound(g, r, 9f, fill, Color.Transparent, 0);

            if (_active)
            {
                RectangleF bar = new RectangleF(r.X + 2f, r.Y + 6f, 3.5f, r.Height - 12f);
                using (GraphicsPath barPath = Gfx.RoundRect(bar.X, bar.Y, bar.Width, bar.Height, 2f))
                {
                    using (LinearGradientBrush lgb = new LinearGradientBrush(bar, Pal.Primary, Pal.PrimaryDeep, LinearGradientMode.Vertical))
                        g.FillPath(lgb, barPath);
                }
            }

            Color gc = _active ? Pal.Primary : (_hot ? Pal.TextMuted : Pal.TextDim);
            Color tc = _active ? Pal.TextMain : (_hot ? Pal.TextMain : Pal.TextMuted);
            if (!Enabled && !_active) { gc = Pal.BorderSoft; tc = Pal.TextDim; }

            if (_iconFont != null && _glyph.Length > 0)
            {
                using (SolidBrush b = new SolidBrush(gc))
                    g.DrawString(_glyph, _iconFont, b, 22f, (Height - _iconFont.GetHeight(g)) / 2f);
            }

            int hintW = 0;
            if (_hint.Length > 0 && (_active || _hot))
            {
                Size hs = TextRenderer.MeasureText(g, _hint, _hintFont, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                hintW = hs.Width + 8;
                Rectangle hr = new Rectangle(Width - 14 - hs.Width, 0, hs.Width + 2, Height);
                TextRenderer.DrawText(g, _hint, _hintFont, hr, Pal.TextDim,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
            }

            if (_label.Length > 0)
            {
                Rectangle tr = new Rectangle(52, 0, Math.Max(10, Width - 60 - hintW), Height);
                TextRenderer.DrawText(g, _label, Font, tr, tc,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left |
                    TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis);
            }

            if (Focused && ShowFocusCues)
            {
                using (Pen p = new Pen(Pal.BorderSoft, 1f))
                using (GraphicsPath fp = Gfx.RoundRect(r.X, r.Y, r.Width, r.Height, 9f))
                    g.DrawPath(p, fp);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_iconFont != null) _iconFont.Dispose();
                if (_hintFont != null) _hintFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }

    // ---------------------------------------------------------------
    // FlatProgress - barra de progresso fina (percentual ou marquee)
    // ---------------------------------------------------------------
    public class FlatProgress : Control
    {
        private int _percent = -1;
        private float _pos = -90f;
        private Timer _timer;
        private Color _fill = Color.Empty;

        public Color TrackColor = Pal.BorderSoft;

        // Cor fixa opcional (ex.: vermelho quando o disco esta cheio). Vazio = gradiente padrao.
        public Color FillColor
        {
            get { return _fill; }
            set { _fill = value; Invalidate(); }
        }

        public int Percent
        {
            get { return _percent; }
            set
            {
                _percent = value;
                SyncTimer();
                Invalidate();
            }
        }

        public FlatProgress()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Height = 6;
        }

        // Marquee so anima quando visivel (economiza CPU nas abas ocultas).
        private void SyncTimer()
        {
            bool need = _percent < 0 && Visible;
            if (need)
            {
                if (_timer == null)
                {
                    _timer = new Timer();
                    _timer.Interval = 20;
                    _timer.Tick += delegate(object s, EventArgs e)
                    {
                        _pos += 7f;
                        if (_pos > Width + 40f) _pos = -90f;
                        Invalidate();
                    };
                }
                _timer.Start();
            }
            else if (_timer != null)
            {
                _timer.Stop();
            }
        }

        protected override void OnVisibleChanged(EventArgs e)
        {
            base.OnVisibleChanged(e);
            SyncTimer();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Gfx.Prep(g);
            Gfx.PaintBg(this, g);
            RectangleF track = new RectangleF(0f, 0f, Width, Height);
            Gfx.FillRound(g, track, Height / 2f, TrackColor, Color.Transparent, 0);

            if (_percent >= 0)
            {
                float w = Width * (float)Math.Min(100, _percent) / 100f;
                if (_percent > 0 && w < Height * 1.5f) w = Height * 1.5f;
                if (w > 1f)
                {
                    RectangleF fillRect = new RectangleF(0f, 0f, w, Height);
                    using (GraphicsPath path = Gfx.RoundRect(fillRect.X, fillRect.Y, fillRect.Width, fillRect.Height, Height / 2f))
                    {
                        if (!_fill.IsEmpty)
                        {
                            using (SolidBrush b = new SolidBrush(_fill)) g.FillPath(b, path);
                        }
                        else
                        {
                            Color c1 = Pal.Primary;
                            Color c2 = Gfx.Lerp(Pal.Primary, Pal.Success, Math.Min(1f, _percent / 100f));
                            using (LinearGradientBrush lgb = new LinearGradientBrush(new RectangleF(0f, 0f, w + 1f, Height), c1, c2, LinearGradientMode.Horizontal))
                                g.FillPath(lgb, path);
                        }
                    }
                }
            }
            else if (Width > 60f)
            {
                float x = Math.Max(-60f, Math.Min(Width, _pos));
                RectangleF fillRect = new RectangleF(x, 0f, 70f, Height);
                using (GraphicsPath path = Gfx.RoundRect(fillRect.X, fillRect.Y, fillRect.Width, fillRect.Height, Height / 2f))
                {
                    using (LinearGradientBrush lgb = new LinearGradientBrush(fillRect, Pal.Primary, Pal.PrimaryDeep, LinearGradientMode.Horizontal))
                        g.FillPath(lgb, path);
                }
            }
            base.OnPaint(e);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _timer != null) _timer.Dispose();
            base.Dispose(disposing);
        }
    }

    // ---------------------------------------------------------------
    // ArcSpinner - indicador circular animado (so gira quando visivel)
    // ---------------------------------------------------------------
    public class ArcSpinner : Control
    {
        private float _angle;
        private Timer _timer;
        public Color ArcColor = Pal.Primary;
        public int Stroke = 3;

        public ArcSpinner()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Size = new Size(26, 26);
            _timer = new Timer();
            _timer.Interval = 20;
            _timer.Tick += delegate(object s, EventArgs e)
            {
                _angle += 14f;
                if (_angle >= 360f) _angle = 0f;
                Invalidate();
            };
        }

        protected override void OnVisibleChanged(EventArgs e)
        {
            base.OnVisibleChanged(e);
            if (Visible) _timer.Start(); else _timer.Stop();
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            if (Visible) _timer.Start();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Gfx.PaintBg(this, g);
            RectangleF r = new RectangleF(Stroke, Stroke, Width - Stroke * 2, Height - Stroke * 2);
            using (Pen track = new Pen(Pal.BorderSoft, Stroke)) g.DrawArc(track, r, 0, 360);
            using (Pen p = new Pen(ArcColor, Stroke)) { p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; g.DrawArc(p, r, _angle, 100); }
            base.OnPaint(e);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _timer != null) _timer.Dispose();
            base.Dispose(disposing);
        }
    }

    // ---------------------------------------------------------------
    // ToggleSwitch - interruptor
    // Correcao 1.3.0: o alvo da animacao era capturado na 1a chamada, e o
    // botao ficava preso no lado errado a partir do 2o clique.
    // ---------------------------------------------------------------
    public class ToggleSwitch : ButtonBase
    {
        private bool _checked;
        private float _pos;
        private Timer _timer;
        private bool _hot;

        public event EventHandler CheckedChanged;

        public bool Checked
        {
            get { return _checked; }
            set
            {
                if (_checked == value) return;
                _checked = value;
                Animate();
                if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
            }
        }

        public ToggleSwitch()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.Selectable, true);
            Size = new Size(40, 22);
            Cursor = Cursors.Hand;
            _pos = 0f;
        }

        private float Travel()
        {
            return Math.Max(0f, Width - Height);
        }

        private void Animate()
        {
            if (!IsHandleCreated || !Visible)
            {
                _pos = _checked ? Travel() : 0f;
                Invalidate();
                return;
            }
            if (_timer == null)
            {
                _timer = new Timer();
                _timer.Interval = 16;
                _timer.Tick += delegate(object s, EventArgs e)
                {
                    float target = _checked ? Travel() : 0f;
                    _pos = _pos + (target - _pos) * 0.4f;
                    if (Math.Abs(_pos - target) < 0.6f) { _pos = target; _timer.Stop(); }
                    Invalidate();
                };
            }
            _timer.Start();
        }

        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e);
            Checked = !Checked;
        }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hot = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hot = false; Invalidate(); }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Gfx.Prep(g);
            Gfx.PaintBg(this, g);
            RectangleF track = new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f);
            Color tc = _checked ? Pal.Success : (_hot ? Gfx.Lerp(Pal.Border, Pal.TextDim, 0.35f) : Pal.Border);
            Color bc = (Focused && ShowFocusCues) ? Pal.Primary : Pal.BorderSoft;
            Gfx.FillRound(g, track, (Height - 1f) / 2f, tc, bc, 1);

            float kd = Height - 6f;
            float kx = 3f + Math.Max(0f, Math.Min(Travel(), _pos));
            RectangleF knob = new RectangleF(kx, 3f, kd, kd);
            using (SolidBrush b = new SolidBrush(Pal.TextMain)) g.FillEllipse(b, knob);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _timer != null) _timer.Dispose();
            base.Dispose(disposing);
        }
    }

    // ---------------------------------------------------------------
    // StatusPill - selo de estado (Em ordem / Atencao / Critico)
    // Mantem a borda direita fixa quando ancorado a direita e o texto muda.
    // ---------------------------------------------------------------
    public class StatusPill : Control
    {
        private Color _tone = Pal.TextDim;

        public Color Tone
        {
            get { return _tone; }
            set { _tone = value; Invalidate(); }
        }

        public StatusPill()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            Font = new Font("Segoe UI", 8f, FontStyle.Bold);
            Size = new Size(60, 22);
        }

        private void AutoFit()
        {
            string t = Text == null ? "" : Text;
            Size s = TextRenderer.MeasureText(t, Font, new Size(int.MaxValue, int.MaxValue),
                                              TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
            int w = s.Width + 32;
            if (w == Width) return;
            bool keepRight = (Anchor & AnchorStyles.Right) == AnchorStyles.Right &&
                             (Anchor & AnchorStyles.Left) != AnchorStyles.Left;
            int right = Right;
            Width = w;
            if (keepRight) Left = right - w;
        }

        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); AutoFit(); Invalidate(); }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); AutoFit(); Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Gfx.Prep(g);
            Gfx.PaintBg(this, g);
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f);
            using (GraphicsPath p = Gfx.RoundRect(r.X, r.Y, r.Width, r.Height, (Height - 1f) / 2f))
            {
                using (SolidBrush b = new SolidBrush(Color.FromArgb(38, _tone))) g.FillPath(b, p);
                using (Pen pen = new Pen(Color.FromArgb(120, _tone), 1f)) { pen.Alignment = PenAlignment.Inset; g.DrawPath(pen, p); }
            }
            float d = 7f;
            using (SolidBrush dot = new SolidBrush(_tone)) g.FillEllipse(dot, 11f, (Height - d) / 2f, d, d);
            Rectangle tr = new Rectangle(24, 0, Math.Max(4, Width - 30), Height);
            TextRenderer.DrawText(g, Text == null ? "" : Text, Font, tr, Gfx.Lerp(_tone, Pal.TextMain, 0.35f),
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding |
                TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
        }
    }
}
