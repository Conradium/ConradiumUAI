using System.Diagnostics;

namespace ProjectUai.Bridge;

internal sealed class MainForm : Form
{
    private static readonly Color Canvas = Color.FromArgb(27, 28, 26);
    private static readonly Color Surface = Color.FromArgb(40, 42, 38);
    private static readonly Color Ink = Color.FromArgb(242, 239, 226);
    private static readonly Color Muted = Color.FromArgb(177, 180, 166);
    private readonly BridgeProcess bridge;
    private readonly Label state = new(), detail = new();
    private readonly Button start = new(), open = new(), stop = new();
    private readonly NotifyIcon tray;
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 1500 };
    private readonly ToolStripMenuItem trayOpen, trayStop;
    private bool busy, refreshing, allowClose, trayHintShown;

    public MainForm(BridgeProcess bridge)
    {
        this.bridge = bridge;
        Text = "UAI Bridge";
        Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application;
        BackColor = Canvas; ForeColor = Ink;
        Font = new Font("Segoe UI", 10);
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(536, 490);
        MinimumSize = new Size(500, 520);
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(28), ColumnCount = 1, RowCount = 8 };
        foreach (int height in new[] { 27, 49, 57, 112, 65, 49 }) layout.RowStyles.Add(new RowStyle(SizeType.Absolute, height));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 27));
        Controls.Add(layout);
        layout.Controls.Add(TextLabel("PROJECT UAI", 9, FontStyle.Bold, Muted), 0, 0);
        layout.Controls.Add(TextLabel("Cowork, one click away.", 23, FontStyle.Bold, Ink), 0, 1);
        layout.Controls.Add(TextLabel("Your Roblox conversation, with room to work.\nStart the bridge and we’ll open your browser.", 10, FontStyle.Regular, Muted), 0, 2);

        var card = new TableLayoutPanel { Dock = DockStyle.Fill, BackColor = Surface, Padding = new Padding(16),
            Margin = new Padding(0, 0, 0, 12), ColumnCount = 1, RowCount = 2 };
        card.RowStyles.Add(new RowStyle(SizeType.Absolute, 27));
        card.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        StyleLabel(state, 12, FontStyle.Bold, Ink);
        StyleLabel(detail, 9, FontStyle.Regular, Muted);
        state.AccessibleName = "Bridge connection status";
        detail.AccessibleName = "Connection instructions";
        card.Controls.Add(state, 0, 0); card.Controls.Add(detail, 0, 1);
        layout.Controls.Add(card, 0, 3);

        StyleButton(start, "Start Cowork", true);
        start.Margin = new Padding(0, 0, 0, 14);
        start.Click += async (_, _) => await StartAsync();
        layout.Controls.Add(start, 0, 4);
        var actions = new TableLayoutPanel { ColumnCount = 3, RowCount = 1, Dock = DockStyle.Fill, Margin = Padding.Empty };
        for (int i = 0; i < 3; i++) actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f / 3));
        StyleButton(open, "Open Cowork"); StyleButton(stop, "Stop bridge");
        var minimize = new Button(); StyleButton(minimize, "Hide to tray");
        open.Click += (_, _) => OpenBrowser();
        stop.Click += async (_, _) => await StopAsync();
        minimize.Click += (_, _) => HideToTray();
        actions.Controls.Add(open, 0, 0); actions.Controls.Add(stop, 1, 0); actions.Controls.Add(minimize, 2, 0);
        layout.Controls.Add(actions, 0, 5);
        layout.Controls.Add(TextLabel("Connects automatically to the updated UAI script.\nRuns only on this computer · Port 28791", 9, FontStyle.Regular, Muted), 0, 6);
        var footer = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Margin = Padding.Empty };
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 96));
        footer.Controls.Add(TextLabel("UAI Bridge 1.0", 9, FontStyle.Regular, Muted), 0, 0);
        var exit = new LinkLabel { Text = "Exit app", Dock = DockStyle.Fill, TextAlign = ContentAlignment.TopRight,
            LinkColor = Ink, ActiveLinkColor = Ink, VisitedLinkColor = Ink, AccessibleName = "Exit app and stop bridge" };
        exit.Click += async (_, _) => await ExitAsync();
        footer.Controls.Add(exit, 1, 0);
        layout.Controls.Add(footer, 0, 7);

        var menu = new ContextMenuStrip();
        menu.Items.Add("Show UAI Bridge", null, (_, _) => RestoreWindow());
        trayOpen = new ToolStripMenuItem("Open Cowork", null, (_, _) => OpenBrowser());
        trayStop = new ToolStripMenuItem("Stop bridge", null, async (_, _) => await StopAsync());
        menu.Items.Add(trayOpen); menu.Items.Add(trayStop); menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, async (_, _) => await ExitAsync());
        tray = new NotifyIcon { Icon = Icon, Text = "UAI Bridge · Stopped", ContextMenuStrip = menu, Visible = true };
        tray.DoubleClick += (_, _) => RestoreWindow();
        bridge.Changed += OnBridgeChanged;
        timer.Tick += async (_, _) =>
        {
            if (refreshing || busy) return;
            refreshing = true;
            try { await bridge.RefreshAsync(); }
            finally { refreshing = false; }
        };
        timer.Start();
        Resize += (_, _) => { if (WindowState == FormWindowState.Minimized) HideToTray(); };
        FormClosing += (_, args) =>
        {
            if (allowClose || args.CloseReason == CloseReason.WindowsShutDown || args.CloseReason == CloseReason.TaskManagerClosing) return;
            if (busy || bridge.BrowserUrl is not null) { args.Cancel = true; HideToTray(); }
        };
        FormClosed += (_, _) =>
        {
            timer.Stop(); timer.Dispose();
            bridge.Changed -= OnBridgeChanged;
            tray.Visible = false; tray.Dispose(); menu.Dispose();
        };
        UpdateState();
    }

    private static Label TextLabel(string text, float size, FontStyle style, Color color)
    {
        var label = new Label { Text = text };
        StyleLabel(label, size, style, color);
        return label;
    }
    private static void StyleLabel(Label label, float size, FontStyle style, Color color)
    {
        label.Dock = DockStyle.Fill; label.Margin = Padding.Empty;
        label.Font = new Font("Segoe UI", size, style); label.ForeColor = color;
        label.AutoEllipsis = false;
    }
    private static void StyleButton(Button button, string text, bool primary = false)
    {
        button.Text = text; button.AccessibleName = text;
        button.Dock = DockStyle.Fill; button.Margin = new Padding(0, 0, 8, 10);
        button.FlatStyle = FlatStyle.Flat; button.FlatAppearance.BorderSize = primary ? 0 : 1;
        button.FlatAppearance.BorderColor = Color.FromArgb(76, 79, 69);
        button.BackColor = primary ? Ink : Canvas; button.ForeColor = primary ? Canvas : Ink;
        button.Font = new Font("Segoe UI", primary ? 12 : 9, primary ? FontStyle.Bold : FontStyle.Regular);
        button.Cursor = Cursors.Hand; button.UseVisualStyleBackColor = false;
    }
    private void OnBridgeChanged()
    {
        if (IsDisposed || !IsHandleCreated) return;
        try { BeginInvoke(UpdateState); } catch (InvalidOperationException) { }
    }
    private void UpdateState()
    {
        state.Text = bridge.State; detail.Text = bridge.Detail;
        state.ForeColor = bridge.State == "Connected to Roblox" ? Color.FromArgb(181, 213, 149) : Ink;
        bool running = bridge.BrowserUrl is not null;
        start.Enabled = !busy && !running;
        start.Text = busy ? "Please wait..." : running ? "Cowork is running" : "Start Cowork";
        open.Enabled = trayOpen.Enabled = running && !busy;
        stop.Enabled = trayStop.Enabled = running && !busy;
        tray.Text = "UAI Bridge · " + bridge.State;
    }
    private async Task StartAsync()
    {
        if (busy) return;
        busy = true; UpdateState();
        try { await bridge.StartAsync(); OpenBrowser(); }
        catch (IOException) { /* The actionable error is already in the status card. */ }
        finally { busy = false; if (!IsDisposed) UpdateState(); }
    }
    private async Task StopAsync()
    {
        if (busy) return;
        busy = true; UpdateState();
        try { await bridge.StopAsync(); }
        finally { busy = false; if (!IsDisposed) UpdateState(); }
    }
    private void OpenBrowser()
    {
        if (bridge.BrowserUrl is not { } url) return;
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            detail.Text = "Windows could not open your browser. Set a default browser, then click Open Cowork.";
        }
    }
    private void HideToTray()
    {
        Hide();
        if (trayHintShown) return;
        trayHintShown = true;
        tray.ShowBalloonTip(3000, "UAI Bridge is in your tray", "Double-click its tray icon to return. Choose Exit to stop the bridge.", ToolTipIcon.Info);
    }
    public void RestoreWindow()
    {
        if (IsDisposed) return;
        Show(); WindowState = FormWindowState.Normal; Activate();
    }
    private async Task ExitAsync()
    {
        if (busy) { RestoreWindow(); return; }
        busy = true; UpdateState();
        await bridge.StopAsync();
        allowClose = true; Close();
    }
    public void RenderPreview(string path)
    {
        StartPosition = FormStartPosition.Manual;
        Location = new Point(-30000, -30000); ShowInTaskbar = false;
        Shown += async (_, _) =>
        {
            await Task.Delay(250);
            using var bitmap = new Bitmap(Width, Height);
            DrawToBitmap(bitmap, new Rectangle(Point.Empty, Size));
            bitmap.Save(Path.GetFullPath(path));
            allowClose = true; Close();
        };
    }
}
