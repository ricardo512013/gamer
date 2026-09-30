// =====================================================================
// Controls.cs - Biblioteca de controles visuais do TI Suite
// Compilada pelo CodeDom do Windows PowerShell 5.1 => somente C# 5
// (sem $"", sem ?., sem nameof, sem expression-bodied members).
// O dev\Build-Release.ps1 gera bin\TISuite.Controls.dll a partir deste
// arquivo; sem a DLL, o 00-Controls.ps1 compila na hora (mais lento).
// =====================================================================
using System;
using System.Collections.Generic;
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
        public static readonly Color TextDim     = Color.FromArgb(128, 142, 163);
        public static readonly Color ConsoleBg   = Color.FromArgb(2, 6, 23);
        public static readonly Color Hover       = Color.FromArgb(36, 52, 77);
        public static readonly Color ActiveRow   = Color.FromArgb(30, 48, 74);
        public static readonly Color OnPrimary   = Color.FromArgb(8, 20, 36);
    }

    // ---------------------------------------------------------------
    // Fontes compartilhadas: uma instancia por estilo para o app todo
    // (nunca descartadas pelos controles).
    // ---------------------------------------------------------------
    internal static class Fonts
    {
        public static readonly Font Button = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        public static readonly Font Item   = new Font("Segoe UI", 9.5f);
        public static readonly Font Hint   = new Font("Segoe UI", 7.5f);
        public static readonly Font Pill   = new Font("Segoe UI", 8f, FontStyle.Bold);
        public static readonly Font Tip    = new Font("Segoe UI", 8.5f);

        private static readonly Dictionary<float, Font> _icons = new Dictionary<float, Font>();

        // Segoe MDL2 Assets por tamanho (cache)
        public static Font Icon(float size)
        {
            if (size <= 0f) return null;
            lock (_icons)
            {
                Font f;
                if (!_icons.TryGetValue(size, out f))
                {
                    f = new Font("Segoe MDL2 Assets", size, FontStyle.Regular);
                    _icons[size] = f;
                }
                return f;
            }
        }
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

        // Lado totalmente transparente usa o RGB do outro lado (so o alpha varia):
        // sem o clarao cinza de Color.Transparent (branco com alpha 0) no meio.
        public static Color Lerp(Color a, Color b, float t)
        {
            if (t < 0f) t = 0f;
            if (t > 1f) t = 1f;
            if (a.A == 0 && b.A != 0) a = Color.FromArgb(0, b.R, b.G, b.B);
            else if (b.A == 0 && a.A != 0) b = Color.FromArgb(0, a.R, a.G, a.B);
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
    // ITaskbarList3 (progresso no botao da barra de tarefas, Windows 7+).
    // Ordem dos metodos = ordem da vtable (ITaskbarList, 2 e 3).
    // ---------------------------------------------------------------
    [ComImport]
    [Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eefaf")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface ITaskbarList3
    {
        // ITaskbarList
        [PreserveSig] int HrInit();
        [PreserveSig] int AddTab(IntPtr hwnd);
        [PreserveSig] int DeleteTab(IntPtr hwnd);
        [PreserveSig] int ActivateTab(IntPtr hwnd);
        [PreserveSig] int SetActiveAlt(IntPtr hwnd);
        // ITaskbarList2
        [PreserveSig] int MarkFullscreenWindow(IntPtr hwnd, [MarshalAs(UnmanagedType.Bool)] bool fFullscreen);
        // ITaskbarList3
        [PreserveSig] int SetProgressValue(IntPtr hwnd, ulong ullCompleted, ulong ullTotal);
        [PreserveSig] int SetProgressState(IntPtr hwnd, int tbpFlags);
        [PreserveSig] int RegisterTab(IntPtr hwndTab, IntPtr hwndMDI);
        [PreserveSig] int UnregisterTab(IntPtr hwndTab);
        [PreserveSig] int SetTabOrder(IntPtr hwndTab, IntPtr hwndInsertBefore);
        [PreserveSig] int SetTabActive(IntPtr hwndTab, IntPtr hwndMDI, uint dwReserved);
        [PreserveSig] int ThumbBarAddButtons(IntPtr hwnd, uint cButtons, IntPtr pButtons);
        [PreserveSig] int ThumbBarUpdateButtons(IntPtr hwnd, uint cButtons, IntPtr pButtons);
        [PreserveSig] int ThumbBarSetImageList(IntPtr hwnd, IntPtr himl);
        [PreserveSig] int SetOverlayIcon(IntPtr hwnd, IntPtr hIcon, [MarshalAs(UnmanagedType.LPWStr)] string pszDescription);
        [PreserveSig] int SetThumbnailTooltip(IntPtr hwnd, [MarshalAs(UnmanagedType.LPWStr)] string pszTip);
        [PreserveSig] int SetThumbnailClip(IntPtr hwnd, IntPtr prcClip);
    }

    // ---------------------------------------------------------------
    // Interop: DPI, janela, arrasto, backdrop escuro, tema das barras,
    // aviso e progresso na barra de tarefas
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
        [DllImport("uxtheme.dll", EntryPoint = "SetWindowTheme", CharSet = CharSet.Unicode)]
        private static extern int SetWindowThemeNative(IntPtr hWnd, string pszSubAppName, string pszSubIdList);
        [DllImport("user32.dll")] private static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

        [StructLayout(LayoutKind.Sequential)]
        private struct FLASHWINFO
        {
            public uint cbSize;
            public IntPtr hwnd;
            public uint dwFlags;
            public uint uCount;
            public uint dwTimeout;
        }

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

        // Cantos arredondados do DWM (Windows 11) + barra escura. False = sem suporte.
        public static bool RoundWindow(Form f)
        {
            int hr = -1;
            try { int v = 2; hr = DwmSetWindowAttribute(f.Handle, 33, ref v, 4); } catch { hr = -1; } // DWMWCP_ROUND
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

        public static void ShowNoActivate(Form f)
        {
            IntPtr h = f.Handle;
            ShowWindow(h, 8); // SW_SHOWNA
        }

        // Pisca o botao da barra de tarefas (3x e fica destacado ate a janela
        // voltar ao primeiro plano). Nada faz se a janela, ou um dialogo dela,
        // ja estiver em primeiro plano.
        public static void FlashTaskbar(Form f)
        {
            try
            {
                if (f == null || f.IsDisposed || !f.IsHandleCreated) return;
                IntPtr h = f.Handle;
                IntPtr fg = GetForegroundWindow();
                for (int i = 0; i < 8 && fg != IntPtr.Zero; i++)
                {
                    if (fg == h) return;
                    fg = GetWindow(fg, 4); // GW_OWNER
                }
                FLASHWINFO fi = new FLASHWINFO();
                fi.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
                fi.hwnd = h;
                fi.dwFlags = 0x2 | 0xC; // FLASHW_TRAY | FLASHW_TIMERNOFG
                fi.uCount = 3;
                fi.dwTimeout = 0;
                FlashWindowEx(ref fi);
            }
            catch { }
        }

        // --- Progresso no botao da barra de tarefas (melhor esforco) ---
        private static ITaskbarList3 _taskbar;
        private static bool _taskbarFailed;

        private static ITaskbarList3 Taskbar()
        {
            if (_taskbar != null || _taskbarFailed) return _taskbar;
            try
            {
                Type t = Type.GetTypeFromCLSID(new Guid("56FDF344-FD6D-11d0-958A-006097C9A090"));
                ITaskbarList3 tb = (ITaskbarList3)Activator.CreateInstance(t);
                tb.HrInit();
                _taskbar = tb;
            }
            catch { _taskbarFailed = true; }
            return _taskbar;
        }

        private static IntPtr TaskbarHandle(Form f)
        {
            if (f == null || f.IsDisposed || !f.IsHandleCreated) return IntPtr.Zero;
            return f.Handle;
        }

        // percent < 0 = indeterminado; 0..100 = barra normal (verde)
        public static void SetTaskbarProgress(Form f, int percent)
        {
            try
            {
                IntPtr h = TaskbarHandle(f);
                if (h == IntPtr.Zero) return;
                ITaskbarList3 tb = Taskbar();
                if (tb == null) return;
                if (percent < 0) { tb.SetProgressState(h, 0x1); return; } // TBPF_INDETERMINATE
                if (percent > 100) percent = 100;
                tb.SetProgressState(h, 0x2); // TBPF_NORMAL
                tb.SetProgressValue(h, (ulong)percent, 100UL);
            }
            catch { }
        }

        public static void ClearTaskbarProgress(Form f)
        {
            try
            {
                IntPtr h = TaskbarHandle(f);
                if (h == IntPtr.Zero) return;
                ITaskbarList3 tb = Taskbar();
                if (tb == null) return;
                tb.SetProgressState(h, 0x0); // TBPF_NOPROGRESS
            }
            catch { }
        }

        // Barra cheia em vermelho (tarefa terminou com erro)
        public static void SetTaskbarError(Form f)
        {
            try
            {
                IntPtr h = TaskbarHandle(f);
                if (h == IntPtr.Zero) return;
                ITaskbarList3 tb = Taskbar();
                if (tb == null) return;
                tb.SetProgressState(h, 0x4); // TBPF_ERROR
                tb.SetProgressValue(h, 100UL, 100UL);
            }
            catch { }
        }
    }

    // ---------------------------------------------------------------
    // TIForm - janela principal sem moldura: redimensiona pelas bordas
    // (faixa de ResizeBorder px livre de filhos via Padding), maximiza
    // respeitando a barra de tarefas do monitor atual e tem sombra.
    // ---------------------------------------------------------------
    public class TIForm : Form
    {
        public int ResizeBorder = 6;

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int x;
            public int y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MINMAXINFO
        {
            public POINT ptReserved;
            public POINT ptMaxSize;
            public POINT ptMaxPosition;
            public POINT ptMinTrackSize;
            public POINT ptMaxTrackSize;
        }

        public TIForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            Padding = new Padding(ResizeBorder);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ClassStyle |= 0x00020000; // CS_DROPSHADOW
                // WS_MINIMIZEBOX | WS_SYSMENU: sem moldura, clicar no icone da barra de
                // tarefas nao minimizava a janela (nada aparece na tela por causa deles)
                cp.Style |= 0x00020000 | 0x00080000;
                return cp;
            }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x84) // WM_NCHITTEST
            {
                base.WndProc(ref m);
                if (WindowState == FormWindowState.Normal && ResizeBorder > 0 && m.Result.ToInt64() == 1) // HTCLIENT
                {
                    int lp = unchecked((int)(long)m.LParam);
                    int sx = unchecked((short)(lp & 0xFFFF));
                    int sy = unchecked((short)((lp >> 16) & 0xFFFF));
                    int hit = HitEdge(PointToClient(new Point(sx, sy)));
                    if (hit != 0) m.Result = new IntPtr(hit);
                }
                return;
            }
            if (m.Msg == 0x24) // WM_GETMINMAXINFO
            {
                base.WndProc(ref m);
                FillMinMax(m.HWnd, m.LParam);
                return;
            }
            base.WndProc(ref m);
        }

        // Codigo HT* da borda sob o ponto (cliente); 0 = miolo. Cantos com pega maior.
        private int HitEdge(Point p)
        {
            int b = ResizeBorder;
            int c = b * 2;
            int w = ClientSize.Width;
            int h = ClientSize.Height;
            if (p.Y < b)
            {
                if (p.X < c) return 13;      // HTTOPLEFT
                if (p.X >= w - c) return 14; // HTTOPRIGHT
                return 12;                   // HTTOP
            }
            if (p.Y >= h - b)
            {
                if (p.X < c) return 16;      // HTBOTTOMLEFT
                if (p.X >= w - c) return 17; // HTBOTTOMRIGHT
                return 15;                   // HTBOTTOM
            }
            if (p.X < b)
            {
                if (p.Y < c) return 13;
                if (p.Y >= h - c) return 16;
                return 10;                   // HTLEFT
            }
            if (p.X >= w - b)
            {
                if (p.Y < c) return 14;
                if (p.Y >= h - c) return 17;
                return 11;                   // HTRIGHT
            }
            return 0;
        }

        // Maximizado = area util do monitor da janela (sem cobrir a barra de tarefas).
        private void FillMinMax(IntPtr hwnd, IntPtr lParam)
        {
            try
            {
                if (lParam == IntPtr.Zero) return;
                MINMAXINFO mmi = (MINMAXINFO)Marshal.PtrToStructure(lParam, typeof(MINMAXINFO));
                Screen s = Screen.FromHandle(hwnd);
                Rectangle wa = s.WorkingArea;
                Rectangle mb = s.Bounds;
                mmi.ptMaxPosition.x = wa.Left - mb.Left;
                mmi.ptMaxPosition.y = wa.Top - mb.Top;
                mmi.ptMaxSize.x = wa.Width;
                mmi.ptMaxSize.y = wa.Height;
                Size min = MinimumSize;
                if (min.Width > 0) mmi.ptMinTrackSize.x = min.Width;
                if (min.Height > 0) mmi.ptMinTrackSize.y = min.Height;
                Marshal.StructureToPtr(mmi, lParam, false);
            }
            catch { }
        }

        // Faixa de redimensionamento so existe na janela normal
        private void SyncPadding()
        {
            if (WindowState == FormWindowState.Minimized) return;
            int want = WindowState == FormWindowState.Maximized ? 0 : Math.Max(0, ResizeBorder);
            if (Padding.All != want) Padding = new Padding(want);
        }

        protected override void OnResize(EventArgs e)
        {
            SyncPadding();
            base.OnResize(e);
        }

        protected override void OnStyleChanged(EventArgs e)
        {
            base.OnStyleChanged(e);
            SyncPadding();
        }
    }

    // ---------------------------------------------------------------
    // TIScrollFlow - FlowLayoutPanel com a barra de rolagem nativa no
    // tema escuro (DarkMode_Explorer, Windows 10 1809+; melhor esforco:
    // em sistemas antigos fica a barra padrao).
    // ---------------------------------------------------------------
    public class TIScrollFlow : FlowLayoutPanel
    {
        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            Native.SetWindowTheme(Handle, "DarkMode_Explorer", null);
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

        public RoundPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(BackdropColor);
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

        // Mesmas flags na medicao e no desenho ('&' aparece como '&')
        private const TextFormatFlags TextFlags = TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix;

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
        private bool _truncated;
        private bool _autoTip = true;
        private bool _tipShown;

        // Dica propria (texto completo quando cortado com reticencias)
        private static ToolTip _tip;
        private static string _tipText = "";

        public int Radius { get { return _radius; } set { _radius = value; Invalidate(); } }
        public float GlyphSize { get { return _glyphSize; } set { _glyphSize = value; RebuildIconFont(); Invalidate(); } }

        // Mostra o texto completo ao parar o mouse quando ele nao coube.
        // Desligue quando o PowerShell ja define uma dica (TITip) no botao.
        public bool AutoTip
        {
            get { return _autoTip; }
            set { _autoTip = value; if (!value) HideTip(); }
        }

        public Kind Style
        {
            get { return _style; }
            set
            {
                _style = value;
                Color target = !Enabled ? Pal.CardAlt : (_hot ? HotColor() : BaseColor());
                if (IsHandleCreated && Visible) Animate(target);
                else { _cur = target; _target = target; }
                Invalidate();
            }
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
            Font = Fonts.Button;
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
            _iconFont = (_glyph.Length > 0 && _glyphSize > 0f) ? Fonts.Icon(_glyphSize) : null;
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

        private bool IsFilled()
        {
            return _style == Kind.Primary || _style == Kind.Danger || _style == Kind.Success;
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

        // Tolerancia 2: o Lerp trunca e, subindo, empaca a 1-2 do alvo (timer eterno).
        // Alvo transparente: basta o alpha zerar (o RGB fica o da cor de origem).
        private static bool Near(Color a, Color b)
        {
            if (b.A == 0) return a.A <= 2;
            return Math.Abs(a.A - b.A) <= 2 &&
                   Math.Abs(a.R - b.R) <= 2 &&
                   Math.Abs(a.G - b.G) <= 2 &&
                   Math.Abs(a.B - b.B) <= 2;
        }

        private void OnAnimTick(object sender, EventArgs e)
        {
            _cur = Gfx.Lerp(_cur, _target, 0.4f);
            if (Near(_cur, _target)) { _cur = _target; _anim.Stop(); }
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
            HideTip();
            if (Enabled) Animate(BaseColor());
            Invalidate();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            HideTip();
            if (e.Button == MouseButtons.Left) { _down = true; Invalidate(); }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            _down = false;
            Invalidate();
        }

        protected override void OnMouseHover(EventArgs e)
        {
            base.OnMouseHover(e);
            string txt = Text == null ? "" : Text;
            if (!_autoTip || !_truncated || txt.Length == 0) return;
            _tipText = txt;
            try { Tip().Show(txt, this, 0, Height + 4, 8000); _tipShown = true; } catch { }
        }

        private void HideTip()
        {
            if (!_tipShown) return;
            _tipShown = false;
            try { if (_tip != null) _tip.Hide(this); } catch { }
        }

        // ToolTip unica da classe, no mesmo visual escuro do TITip do PowerShell
        private static ToolTip Tip()
        {
            if (_tip == null)
            {
                _tip = new ToolTip();
                _tip.OwnerDraw = true;
                _tip.Popup += delegate(object s, PopupEventArgs pe)
                {
                    Size sz = TextRenderer.MeasureText(_tipText, Fonts.Tip, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPrefix);
                    pe.ToolTipSize = new Size(sz.Width + 18, sz.Height + 12);
                };
                _tip.Draw += delegate(object s, DrawToolTipEventArgs de)
                {
                    Graphics g = de.Graphics;
                    using (SolidBrush b = new SolidBrush(Pal.CardAlt)) g.FillRectangle(b, de.Bounds);
                    using (Pen p = new Pen(Pal.Border)) g.DrawRectangle(p, 0, 0, de.Bounds.Width - 1, de.Bounds.Height - 1);
                    TextRenderer.DrawText(g, de.ToolTipText, Fonts.Tip, de.Bounds, Pal.TextMain,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                };
            }
            return _tip;
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (!e.Handled && e.KeyCode == Keys.Enter && !e.Alt && !e.Control)
            {
                PerformClick();
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
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
            HideTip();
            Invalidate();
        }

        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

        // Mede icone e texto com as mesmas regras do OnPaint; devolve a largura do icone (+8 com texto)
        private float MeasureContent(Graphics g, out SizeF glyph, out Size text)
        {
            string txt = Text == null ? "" : Text;
            glyph = SizeF.Empty;
            float iconW = 0f;
            if (_glyph.Length > 0 && _iconFont != null)
            {
                glyph = g.MeasureString(_glyph, _iconFont, PointF.Empty, StringFormat.GenericTypographic);
                iconW = glyph.Width + (txt.Length > 0 ? 8f : 0f);
            }
            text = txt.Length > 0 ? TextRenderer.MeasureText(g, txt, Font, new Size(int.MaxValue, int.MaxValue), TextFlags) : Size.Empty;
            return iconW;
        }

        // Largura que cabe icone + texto sem reticencias (altura = a atual)
        public override Size GetPreferredSize(Size proposedSize)
        {
            SizeF gs;
            Size ts;
            float iconW;
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
            {
                Gfx.Prep(g);
                iconW = MeasureContent(g, out gs, out ts);
            }
            return new Size((int)Math.Ceiling(iconW) + ts.Width + 32, Height);
        }

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
                    if (Enabled && IsFilled())
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
                    // Nos estilos cheios o anel escuro contrasta com o fundo colorido
                    Color ring = IsFilled() ? Color.FromArgb(210, Pal.OnPrimary) : Gfx.Lerp(border, Pal.Primary, 0.85f);
                    using (Pen p = new Pen(ring, 1.5f))
                    {
                        using (GraphicsPath inner = Gfx.RoundRect(r.X + 2f, r.Y + 2f, r.Width - 4f, r.Height - 4f, _radius - 2f))
                            g.DrawPath(p, inner);
                    }
                }
            }

            // Medicao e desenho com o MESMO motor (GDI/TextRenderer): texto centralizado de verdade.
            string txt = Text == null ? "" : Text;
            SizeF gs;
            Size ts;
            float iconW = MeasureContent(g, out gs, out ts);
            float total = iconW + ts.Width;
            float x0 = Math.Max(10f, (Width - total) / 2f);

            if (iconW > 0f)
            {
                using (SolidBrush b = new SolidBrush(tc))
                    g.DrawString(_glyph, _iconFont, b, x0, (Height - gs.Height) / 2f + 0.5f, StringFormat.GenericTypographic);
            }
            bool cut = false;
            if (ts.Width > 0)
            {
                Rectangle tr = new Rectangle((int)(x0 + iconW), 0, Math.Max(4, (int)(Width - x0 - iconW - 6)), Height);
                cut = ts.Width > tr.Width;
                TextRenderer.DrawText(g, txt, Font, tr, tc,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFlags | TextFormatFlags.EndEllipsis);
            }
            _truncated = cut;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                HideTip();
                if (_anim != null) _anim.Dispose();
            }
            base.Dispose(disposing);
        }
    }

    // ---------------------------------------------------------------
    // SidebarItem - item de navegacao com barra de acento e atalho.
    // Teclado: Enter/Espaco abre; Cima/Baixo/Home/End andam entre os
    // itens visiveis (pula os ocultos pela busca).
    // ---------------------------------------------------------------
    public class SidebarItem : ButtonBase
    {
        private string _glyph = "";
        private string _label = "";
        private string _hint = "";
        private bool _active;
        private bool _hot;
        private Font _iconFont;

        public string Glyph
        {
            get { return _glyph; }
            set { _glyph = value == null ? "" : value; _iconFont = _glyph.Length > 0 ? Fonts.Icon(13f) : null; Invalidate(); }
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
            Font = Fonts.Item;
        }

        // Igual ao PremiumButton.PerformClick
        public void PerformClick()
        {
            if (Enabled && Visible) OnClick(EventArgs.Empty);
        }

        protected override bool IsInputKey(Keys keyData)
        {
            switch (keyData)
            {
                case Keys.Up:
                case Keys.Down:
                case Keys.Home:
                case Keys.End:
                    return true;
            }
            return base.IsInputKey(keyData);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.Handled) return;
            if (e.KeyCode == Keys.Enter && !e.Alt && !e.Control)
            {
                PerformClick();
            }
            else if (e.Modifiers == Keys.None &&
                     (e.KeyCode == Keys.Up || e.KeyCode == Keys.Down || e.KeyCode == Keys.Home || e.KeyCode == Keys.End))
            {
                MoveFocus(e.KeyCode);
            }
            else return;
            e.Handled = true;
            e.SuppressKeyPress = true;
        }

        // Foco no item irmao visivel/habilitado anterior, seguinte, primeiro ou ultimo
        private void MoveFocus(Keys key)
        {
            Control p = Parent;
            if (p == null) return;
            List<SidebarItem> items = new List<SidebarItem>();
            foreach (Control c in p.Controls)
            {
                SidebarItem si = c as SidebarItem;
                if (si != null && (si == this || (si.Visible && si.Enabled))) items.Add(si);
            }
            int idx = items.IndexOf(this);
            SidebarItem target = null;
            if (key == Keys.Home) target = items[0];
            else if (key == Keys.End) target = items[items.Count - 1];
            else if (key == Keys.Up && idx > 0) target = items[idx - 1];
            else if (key == Keys.Down && idx >= 0 && idx < items.Count - 1) target = items[idx + 1];
            if (target == null || target == this) return;
            target.Focus();
            ScrollableControl sc = p as ScrollableControl;
            if (sc != null && sc.AutoScroll) sc.ScrollControlIntoView(target);
        }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hot = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hot = false; Invalidate(); }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

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
                Font hf = Fonts.Hint;
                Size hs = TextRenderer.MeasureText(g, _hint, hf, new Size(int.MaxValue, int.MaxValue),
                                                   TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
                hintW = hs.Width + 8;
                Rectangle hr = new Rectangle(Width - 14 - hs.Width, 0, hs.Width + 2, Height);
                TextRenderer.DrawText(g, _hint, hf, hr, Pal.TextDim,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
            }

            if (_label.Length > 0)
            {
                Rectangle tr = new Rectangle(52, 0, Math.Max(10, Width - 60 - hintW), Height);
                TextRenderer.DrawText(g, _label, Font, tr, tc,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left |
                    TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }

            if (Focused && ShowFocusCues)
            {
                using (Pen p = new Pen(Color.FromArgb(180, Pal.Primary), 1f))
                using (GraphicsPath fp = Gfx.RoundRect(r.X, r.Y, r.Width, r.Height, 9f))
                    g.DrawPath(p, fp);
            }
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
        // OnVisibleChanged (tambem disparado quando um pai aparece/some) religa.
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
                        if (!Visible || _percent >= 0) { _timer.Stop(); return; }
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
                // Visible reflete os pais: aba/painel oculto para o giro
                if (!Visible) { _timer.Stop(); return; }
                _angle += 14f;
                if (_angle >= 360f) _angle = 0f;
                Invalidate();
            };
        }

        // Tambem disparado quando um pai aparece/some: religa ao voltar a ficar visivel
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

        // Enter alterna como o Espaco
        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (!e.Handled && e.KeyCode == Keys.Enter && !e.Alt && !e.Control)
            {
                if (Enabled && Visible) OnClick(EventArgs.Empty);
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }

        // Tamanho mudou fora da animacao: botao no fim do trilho certo
        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (_timer == null || !_timer.Enabled) _pos = _checked ? Travel() : 0f;
            Invalidate();
        }

        protected override void OnEnabledChanged(EventArgs e)
        {
            base.OnEnabledChanged(e);
            Cursor = Enabled ? Cursors.Hand : Cursors.Default;
            _hot = false;
            Invalidate();
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
            Color tc;
            Color kc;
            if (Enabled)
            {
                tc = _checked ? Pal.Success : (_hot ? Gfx.Lerp(Pal.Border, Pal.TextDim, 0.35f) : Pal.Border);
                kc = Pal.TextMain;
            }
            else
            {
                // Desabilitado: apagado, sem hover
                tc = _checked ? Gfx.Lerp(Pal.Success, Pal.Card, 0.55f) : Pal.BorderSoft;
                kc = Pal.TextDim;
            }
            Color bc = (Enabled && Focused && ShowFocusCues) ? Pal.Primary : Pal.BorderSoft;
            Gfx.FillRound(g, track, (Height - 1f) / 2f, tc, bc, 1);

            float kd = Height - 6f;
            float kx = 3f + Math.Max(0f, Math.Min(Travel(), _pos));
            RectangleF knob = new RectangleF(kx, 3f, kd, kd);
            using (SolidBrush b = new SolidBrush(kc)) g.FillEllipse(b, knob);
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
    // Fundo transparente: o WinForms pinta o pai (card com brilho) por baixo.
    // ---------------------------------------------------------------
    public class StatusPill : Control
    {
        private Color _tone = Pal.TextDim;

        private const TextFormatFlags TextFlags = TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix;

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
            BackColor = Color.Transparent;
            Font = Fonts.Pill;
            Size = new Size(60, 22);
        }

        private void AutoFit()
        {
            string t = Text == null ? "" : Text;
            Size s = TextRenderer.MeasureText(t, Font, new Size(int.MaxValue, int.MaxValue), TextFlags);
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
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFlags | TextFormatFlags.EndEllipsis);
        }
    }

    // ---------------------------------------------------------------
    // Menus de contexto no tema escuro (o padrao do WinForms e' claro)
    // ---------------------------------------------------------------
    public class DarkMenuColors : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return Pal.CardAlt; } }
        public override Color ImageMarginGradientBegin { get { return Pal.CardAlt; } }
        public override Color ImageMarginGradientMiddle { get { return Pal.CardAlt; } }
        public override Color ImageMarginGradientEnd { get { return Pal.CardAlt; } }
        public override Color MenuBorder { get { return Pal.Border; } }
        public override Color MenuItemBorder { get { return Pal.BorderSoft; } }
        public override Color MenuItemSelected { get { return Pal.Hover; } }
        public override Color MenuItemSelectedGradientBegin { get { return Pal.Hover; } }
        public override Color MenuItemSelectedGradientEnd { get { return Pal.Hover; } }
        public override Color MenuItemPressedGradientBegin { get { return Pal.ActiveRow; } }
        public override Color MenuItemPressedGradientEnd { get { return Pal.ActiveRow; } }
        public override Color SeparatorDark { get { return Pal.BorderSoft; } }
        public override Color SeparatorLight { get { return Pal.BorderSoft; } }
    }

    public class DarkMenuRenderer : ToolStripProfessionalRenderer
    {
        public DarkMenuRenderer() : base(new DarkMenuColors()) { RoundedEdges = false; }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Enabled ? Pal.TextMain : Pal.TextDim;
            base.OnRenderItemText(e);
        }
    }
}
