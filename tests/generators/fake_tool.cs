// Copyright (c) Microsoft Corporation. All rights reserved.
using System;
using System.IO;
using System.Collections.Generic;
using System.Web.Script.Serialization;

class FakeTool
{
    static string ValueAfter(string[] args, string name)
    {
        int index = Array.IndexOf(args, name);
        return index < 0 ? null : args[index + 1];
    }

    static int Main(string[] args)
    {
        string kind = ValueAfter(args, "--kind");
        string log = ValueAfter(args, "--log");
        File.AppendAllText(log, new JavaScriptSerializer().Serialize(args) + Environment.NewLine);
        if (kind == "fail") return 23;
        var outputs = new List<string>();
        switch (kind)
        {
            case "midl":
                if (!File.Exists(args[args.Length - 1])) throw new FileNotFoundException("IDL input");
                outputs.Add(ValueAfter(args, "/winmd"));
                break;
            case "merge":
                if (!File.Exists(ValueAfter(args, "-i"))) throw new FileNotFoundException("Merge input");
                outputs.AddRange(ValueAfter(args, "--outputs").Split('|'));
                break;
            case "component":
                outputs.AddRange(ValueAfter(args, "--outputs").Split('|'));
                outputs.Add(Path.Combine(ValueAfter(args, "-out"), "module.g.cpp"));
                break;
            case "pri":
                if (!File.Exists(ValueAfter(args, "-ConfigXml"))) throw new FileNotFoundException("PRI config");
                outputs.Add(ValueAfter(args, "-OutputFile"));
                break;
            default: throw new ArgumentException("Unknown fake tool kind");
        }
        foreach (string output in outputs)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(output));
            File.WriteAllText(output, "synthetic " + kind + " output");
        }
        return 0;
    }
}
