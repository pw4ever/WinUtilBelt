using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using Mono.Options;
using WindowsInput;

namespace NeverIdle
{
    class Program
    {
        static InputSimulator inputSim = new InputSimulator();
        static Random rnd = new Random(DateTime.Now.Millisecond);
        static Options options = new Options {
            keyCode = WindowsInput.Native.VirtualKeyCode.NONAME,
            minDelay = 1,
            maxDelay = 30,
        };

        static void Main(string[] args)
        {
            // Parse options.
            try
            {
                optionSet.Parse(args);
            }
            catch (OptionException e)
            {
                Console.Error.WriteLine(e.Message);
                Usage(null, ExitCode.OptionParsingError);
            }

            // Validate options.
            try
            {
                if (options.helpP) { Usage(null, ExitCode.Success, true); }
                {
                    var tmp = new List<int> { options.minDelay, options.maxDelay };
                    options.minDelay = Math.Max(0, Math.Abs(tmp.Min()));
                    options.maxDelay = Math.Max(0, Math.Abs(tmp.Max()));
                }
            }
            catch (Exception e)
            {
                Usage(e.Message, ExitCode.OptionValidationError);
            }

            // Do real work.
            try
            {
                int delay = options.maxDelay;
                do
                {
                    if (!options.noDefaultP)
                    {
                        try
                        {
                            inputSim.Mouse.MoveMouseBy(0, 0);
                            if (options.verbosity > 1) { Console.Out.WriteLine($"Sent Mouse.MoveMouseBy(0, 0)."); }
                        }
                        catch (Exception e)
                        {
                            if (options.verbosity > 0) { Console.Error.WriteLine(e.Message); }
                        }
                    }

                    if (options.sendKeyP)
                    {
                        try {
                            inputSim.Keyboard.KeyPress(options.keyCode);
                            if (options.verbosity > 1) { Console.Out.WriteLine($"Sent Keyboard.KeyPress on {options.keyCode}."); }
                        }
                        catch (Exception e)
                        {
                            if (options.verbosity > 0) { Console.Error.WriteLine(e.Message); }
                        }
                    }

                    if (options.onceP) { break; }

                    if (!options.noRandomDelayP)
                    {
                        delay = rnd.Next(options.minDelay, options.maxDelay);
                    }
                    if (options.verbosity > 0) { Console.Out.WriteLine($"Delay for {delay} seconds before sending next event."); }
                    Thread.Sleep(1000 * delay);

                } while (!options.onceP);
            }
            catch (Exception e)
            {
                Usage(e.Message, ExitCode.OtherError);
            }
        }

        static void Usage(string message, ExitCode code, bool showHelp = false)
        {
            if (message != null)
            {
                Console.Error.WriteLine($"{message}");
            }

            if (showHelp)
            {
                if (message != null) { Console.Error.WriteLine(""); }

                Console.Out.WriteLine("Windows keyboard/mouse event sender.");
                Console.Out.WriteLine("Author/maintainer: Wei Peng <write.to.peng.wei@gmail.com>");

                Console.Out.WriteLine("\nCommand-line options:");
                optionSet.WriteOptionDescriptions(Console.Out);

                Console.Out.WriteLine("\nOption values:");
                foreach (var f in options.GetType().GetFields())
                {
                    Console.Out.WriteLine($"{f.Name}={f.GetValue(options)}");
                }

                Console.Out.WriteLine("\nExit values:");
                foreach (var v in Enum.GetValues(typeof(ExitCode)))
                {
                    Console.Out.WriteLine("0x{0:X08}\t{1}", (int)v, (ExitCode)v);
                }

                Console.Out.WriteLine("\nVirtual keycode names:");
                Console.Out.WriteLine(String.Join(" ", Enum.GetNames(typeof(WindowsInput.Native.VirtualKeyCode))));
            }

            Environment.Exit((int)code);
        }

        static OptionSet optionSet = new OptionSet
        {
            {
                "k|keycode=",
                "Virtual key code name (WindowsInput.Native.VirtualKeyCode enum symbolic name) to send.",
                x => {
                    if (!String.IsNullOrWhiteSpace(x)) {
                        options.sendKeyP = true;
                        try {
                        options.keyCode = (WindowsInput.Native.VirtualKeyCode)Enum.Parse(typeof(WindowsInput.Native.VirtualKeyCode), x.ToString().ToUpper());
                        }
                        catch (Exception e) {
                            Console.Error.WriteLine(e.Message);
                            Console.Error.WriteLine("Key code reverts to {0}.", options.keyCode);
                        }
                    }
                }
            },
            {
                "d|noDefault",
                "Do not send the default event.",
                x => options.noDefaultP = (x!= null)            },
            {
                "1|once",
                "Send event once and exit immediately, rather than indefinitely looping.",
                x => options.onceP = (x != null)
            },
            {
                "minDelay=",
                "Minimal delay in seconds between cycles.",
                x => {
                    try {
                        options.minDelay = int.Parse(x);
                    }
                    catch (Exception e) {
                        Console.Error.WriteLine(e.Message);
                        Console.Error.WriteLine("Minimal delay reverts to {0}.", options.minDelay);
                    }
                }
            },
            {
                "maxDelay=",
                "Maximal delay in seconds between cycles.",
                x => {
                    try {
                        options.maxDelay = int.Parse(x);
                    }
                    catch (Exception e) {
                        Console.Error.WriteLine(e.Message);
                        Console.Error.WriteLine("Maximal eelay reverts to {0}.", options.maxDelay);
                    }
                }
            },
            {
                "r|noRandomDelay",
                "Delay by max delay seconds between cycles, rather than by a random amount between min and max delay.",
                x => options.noRandomDelayP = (x != null)
            },
            {
                "v|verbose",
                "Being verbose; stacking to increase verbosity.",
                x => {
                    if (x != null)
                    {
                        options.verbosity ++;
                    }
                }
            },
            {
                "h|help",
                "Get help; you are reading it.",
                x => options.helpP = (x != null)
            },
        };

        struct Options
        {
            public bool noDefaultP;
            public bool sendKeyP;
            public WindowsInput.Native.VirtualKeyCode keyCode;
            public bool onceP;
            public int minDelay;
            public int maxDelay;
            public bool noRandomDelayP;
            public int verbosity;
            public bool helpP;
        }

        enum ExitCode : int
        {
            Success = 0,
            OptionParsingError = 1,
            OptionValidationError = 2,
            OtherError = -1
        }
    }
}
