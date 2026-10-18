// .NET Framework Windows session notifications for Yeelight Bilina.
// SessionEnding runs BEFORE Windows closes the user session and network.
// Intended for interactive Windows PowerShell 5.1; no admin permissions.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace YeelightBilina
{
    public static class WindowsShutdownWhite
    {
        private static string[] ips = new string[0];
        private static int port = 55443;
        private static int kelvin = 4000;
        private static int brightness = 100;
        private static string logFile = "";
        private static int startSeen = 0;
        private static int endSeen = 0;
        private static readonly object logLock = new object();
        private static readonly Regex idRegex = new Regex("\\\"id\\\"\\s*:\\s*(\\d+)", RegexOptions.Compiled);
        private static readonly Regex resultRegex = new Regex("\\\"result\\\"\\s*:", RegexOptions.Compiled);
        private static readonly Regex errorRegex = new Regex("\\\"error\\\"\\s*:", RegexOptions.Compiled);

        public static void Register(string[] addresses, int colorTemperature, int percent, int tcpPort, string logPath)
        {
            if (addresses == null || addresses.Length == 0)
                throw new ArgumentException("No bulb IPs");
            ips = (string[])addresses.Clone();
            kelvin = colorTemperature;
            brightness = percent;
            port = tcpPort;
            logFile = logPath;
            // Windows SystemEvents uses its own message window / event thread.
            // This works while PowerShell's regular process watcher is asleep.
            SystemEvents.SessionEnding += OnSessionEnding;
            SystemEvents.SessionEnded += OnSessionEnded;
            WriteLog("WINDOWS_SHUTDOWN_LISTENER_REGISTERED");
        }

        private static void OnSessionEnding(object sender, SessionEndingEventArgs args)
        {
            if (Interlocked.Exchange(ref startSeen, 1) == 0)
                RestoreNow("WINDOWS_SESSION_ENDING");
        }

        private static void OnSessionEnded(object sender, SessionEndedEventArgs args)
        {
            if (Interlocked.Exchange(ref endSeen, 1) == 0)
                RestoreNow("WINDOWS_SESSION_ENDED");
        }

        // Regression test hook: executes exactly the SAME send path as both OS events.
        // Does not shut down Windows.
        public static bool SimulateForTest()
        {
            return RestoreNow("SIMULATED_WINDOWS_SESSION_ENDING")
                && RestoreNow("SIMULATED_WINDOWS_SESSION_ENDED");
        }

        private static void WriteLog(string message)
        {
            var text = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine;
            lock (logLock)
            {
                try
                {
                    var folder = Path.GetDirectoryName(logFile);
                    if (!String.IsNullOrEmpty(folder)) Directory.CreateDirectory(folder);
                    File.AppendAllText(logFile, text, new UTF8Encoding(false));
                }
                catch { /* Shutdown may revoke access to profile storage. */ }
            }
        }

        private static bool RestoreNow(string stage)
        {
            WriteLog(stage + " - restoring native white before network shutdown");
            var results = new bool[ips.Length];
            var tasks = new Task[ips.Length];
            for (int i = 0; i < ips.Length; i++)
            {
                int index = i;
                tasks[i] = Task.Run(() => { results[index] = RestoreWithRetry(ips[index]); });
            }
            // Three devices in parallel, bounded so Windows is not blocked indefinitely.
            try { Task.WaitAll(tasks, 6900); }
            catch (Exception ex) { WriteLog("WINDOWS_SHUTDOWN_EXCEPTION: " + ex.Message); }
            bool ok = true;
            for (int i = 0; i < tasks.Length; i++)
                if (!tasks[i].IsCompleted || !results[i]) ok = false;
            WriteLog(stage + (ok ? " OK" : " FAILED_OR_TIMED_OUT"));
            return ok;
        }

        // Each bulb gets an independent retry, without delaying successful bulbs.
        // A device may still be occupied by SignalRGB's previous UDP session.
        private static bool RestoreWithRetry(string ip)
        {
            if (RestoreOne(ip)) return true;
            Thread.Sleep(500);
            if (RestoreOne(ip)) return true;
            Thread.Sleep(500);
            return RestoreOne(ip);
        }

        private static bool RestoreOne(string ip)
        {
            TcpClient client = null;
            try
            {
                client = new TcpClient();
                IAsyncResult pending = client.BeginConnect(ip, port, null, null);
                using (pending.AsyncWaitHandle)
                {
                    if (!pending.AsyncWaitHandle.WaitOne(950)) throw new IOException("TCP timeout");
                }
                client.EndConnect(pending);
                client.ReceiveTimeout = 850;
                client.SendTimeout = 850;
                using (NetworkStream stream = client.GetStream())
                using (var writer = new StreamWriter(stream, new UTF8Encoding(false), 1024, true))
                using (var reader = new StreamReader(stream, Encoding.UTF8, false, 1024, true))
                {
                    writer.NewLine = "\r\n";
                    writer.AutoFlush = true;
                    SendAndConfirm(writer, reader, 1, "set_power", "[\"on\",\"sudden\",0]");
                    SendAndConfirm(writer, reader, 2, "set_ct_abx", "[" + kelvin + ",\"smooth\",300]");
                    SendAndConfirm(writer, reader, 3, "set_bright", "[" + brightness + ",\"smooth\",300]");
                }
                WriteLog("WINDOWS_WHITE_OK " + ip + " " + kelvin + "K " + brightness + "%");
                return true;
            }
            catch (Exception ex)
            {
                WriteLog("WINDOWS_WHITE_FAILED " + ip + " " + ex.GetType().Name + ": " + ex.Message);
                return false;
            }
            finally
            {
                if (client != null) client.Close();
            }
        }

        private static void SendAndConfirm(StreamWriter w, StreamReader r, int id, string method, string parameters)
        {
            w.WriteLine("{\"id\":" + id + ",\"method\":\"" + method + "\",\"params\":" + parameters + "}");
            string reply = r.ReadLine();
            if (String.IsNullOrEmpty(reply) || errorRegex.IsMatch(reply) || !resultRegex.IsMatch(reply))
                throw new IOException("Invalid response to " + method + ": " + reply);
            Match idMatch = idRegex.Match(reply);
            if (!idMatch.Success || Int32.Parse(idMatch.Groups[1].Value) != id)
                throw new IOException("Wrong response id for " + method + ": " + reply);
        }
    }
}
