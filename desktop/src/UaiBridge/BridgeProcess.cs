using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ProjectUai.Bridge;

internal sealed class BridgeProcess : IAsyncDisposable
{
    public const int Port = 28791;
    public const string Origin = "http://127.0.0.1:28791";
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly HttpClient http = new(new HttpClientHandler { UseProxy = false, AllowAutoRedirect = false })
        { Timeout = TimeSpan.FromSeconds(3) };
    private Process? child;
    private ChildJob? job;
    private volatile bool stopping;
    private string? token;
    public string State { get; private set; } = "Stopped";
    public string Detail { get; private set; } = "Ready when you are.";
    public string? BrowserUrl => token is { } secret ? Origin + "/#t=" + secret : null;
    public event Action? Changed;

    private void SetState(string state, string detail)
    {
        State = state;
        Detail = detail;
        Changed?.Invoke();
    }

    public async Task StartAsync()
    {
        await gate.WaitAsync();
        try
        {
            if (child is { HasExited: false }) return;
            child?.Dispose(); child = null;
            job?.Dispose(); job = null;
            token = null;
            SetState("Starting", "Starting your local Cowork bridge...");
            string root = AppContext.BaseDirectory;
            string node = Path.Combine(root, "runtime", "node.exe");
            string server = Path.Combine(root, "bridge", "server.js");
            if (!File.Exists(node) || !File.Exists(server))
                throw new IOException("The app package is incomplete. Extract the entire ZIP, then open UAI Bridge.exe inside that folder.");

            var ready = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            var process = new Process { StartInfo = new ProcessStartInfo(node)
            {
                WorkingDirectory = root, UseShellExecute = false, CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden, RedirectStandardInput = true,
                RedirectStandardOutput = true, RedirectStandardError = true
            }, EnableRaisingEvents = true };
            process.StartInfo.ArgumentList.Add(server);
            process.StartInfo.ArgumentList.Add("--desktop");
            process.Exited += (_, _) =>
            {
                if (ReferenceEquals(child, process) && !stopping)
                {
                    token = null;
                    SetState("Could not connect", "The bridge stopped unexpectedly. Click Start Cowork to restart it.");
                }
            };
            try { process.Start(); }
            catch { process.Dispose(); throw; }
            child = process;
            job = new ChildJob(process);
            _ = ReadOutputAsync(process, ready);
            // Drain stderr without recording potentially sensitive process output.
            _ = DrainErrorsAsync(process);
            string secret = await ready.Task.WaitAsync(TimeSpan.FromSeconds(12));
            if (process.HasExited) throw new IOException("The bridge exited during startup. Try again.");
            token = secret;
            SetState("Waiting for Roblox", "Load the updated UAI script in Roblox. It will connect automatically.");
        }
        catch (Exception error)
        {
            await StopCoreAsync();
            string detail = error is TimeoutException
                ? "The bridge took too long to start. Try again or extract a fresh copy of the app."
                : error.Message;
            SetState("Could not start", detail);
            throw new IOException(detail);
        }
        finally { gate.Release(); }
    }

    private static async Task DrainErrorsAsync(Process process)
    {
        try { while (await process.StandardError.ReadLineAsync() is not null) { } }
        catch (Exception error) when (error is IOException or ObjectDisposedException or InvalidOperationException) { }
    }

    private static async Task ReadOutputAsync(Process process, TaskCompletionSource<string> ready)
    {
        try
        {
            while (await process.StandardOutput.ReadLineAsync() is { } line)
            {
                if (line.Length > 8192) continue;
                using var doc = JsonDocument.Parse(line);
                var value = doc.RootElement;
                if (value.GetProperty("type").GetString() == "error")
                {
                    string message = value.GetProperty("message").GetString() ?? "The bridge could not start.";
                    ready.TrySetException(new IOException(message));
                }
                else if (value.GetProperty("type").GetString() == "ready")
                {
                    string secret = value.GetProperty("token").GetString() ?? "";
                    if (value.GetProperty("product").GetString() != "project-uai-desktop" ||
                        value.GetProperty("protocol").GetInt32() != 1 || value.GetProperty("port").GetInt32() != Port ||
                        !Regex.IsMatch(secret, "\\A[a-f0-9]{64}\\z") ||
                        value.GetProperty("url").GetString() != Origin + "/#t=" + secret)
                        throw new IOException("The bridge package is incompatible. Extract a fresh copy of the app.");
                    ready.TrySetResult(secret);
                }
            }
        }
        catch (Exception error) when (error is IOException or JsonException or KeyNotFoundException or InvalidOperationException)
        { ready.TrySetException(new IOException("The bridge returned an invalid startup response.")); }
        finally { ready.TrySetException(new IOException("The bridge stopped before it was ready. Try starting it again.")); }
    }

    public async Task RefreshAsync()
    {
        string? secret = token;
        if (secret is null || stopping) return;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, Origin + "/api/hello");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", secret);
            using var response = await http.SendAsync(request);
            response.EnsureSuccessStatusCode();
            using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            bool connected = doc.RootElement.GetProperty("connected").GetBoolean();
            if (secret != token || stopping) return;
            SetState(connected ? "Connected to Roblox" : "Waiting for Roblox", connected
                ? "Your conversation is ready in Cowork. Keep Roblox and this app running."
                : "Load the updated UAI script in Roblox. It will connect automatically.");
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or JsonException or KeyNotFoundException or InvalidOperationException)
        {
            if (secret == token && !stopping)
                SetState("Reconnecting", "The bridge is not responding. If this continues, stop it and start it again.");
        }
    }

    public async Task StopAsync()
    {
        await gate.WaitAsync();
        try
        {
            SetState("Stopping", "Closing the local bridge...");
            await StopCoreAsync();
            SetState("Stopped", "Ready when you are.");
        }
        finally { gate.Release(); }
    }

    private async Task StopCoreAsync()
    {
        stopping = true;
        token = null;
        var process = child;
        try
        {
            if (process is not null && !process.HasExited)
            {
                try
                {
                    await process.StandardInput.WriteLineAsync("{\"type\":\"stop\"}");
                    await process.StandardInput.FlushAsync();
                    await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(4));
                }
                catch (Exception error) when (error is IOException or InvalidOperationException or TimeoutException)
                {
                    if (!process.HasExited) process.Kill(entireProcessTree: true);
                    await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3));
                }
            }
        }
        finally
        {
            job?.Dispose(); job = null;
            child = null;
            process?.Dispose();
            stopping = false;
        }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync();
        http.Dispose();
        gate.Dispose();
    }
}
