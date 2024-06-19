import std.algorithm;
import std.conv: to;
import std.string: chomp;
import std.range;
import std.stdio;

struct CliOptions
{
    bool refs_as_comments;
    bool prepr_refs_comments;
    bool suppress_refs;
}

int main(string[] args)
{
    import std.getopt;

    CliOptions options;

    {
        //TODO: replace by option for files splitten by zero byte
        auto helpInformation = getopt(args,
            "refs_as_comments", `"Add // before # 123 "/path/to/file.h" lines"`, &options.refs_as_comments,
            "prepr_refs_comments", `Add comment lines with references to a preprocessed files`, &options.prepr_refs_comments,
            "suppress_refs", `Suppress # 123 "/path/to/file.h" lines`, &options.suppress_refs,
        );

        if (helpInformation.helpWanted)
        {
            defaultGetoptPrinter(`Usage: `~args[0]~" [PARAMETER]...\n"~
                `Takes a list of AST files from STDIN and returns merged preprocessed file`,
                helpInformation.options);

            return 0;
        }
    }

    import std.parallelism;

    defaultPoolThreads(6);

    const filenames = stdin.byLineCopy.array; //TODO: use asyncBuf
    auto initialASTs = taskPool.amap!createAST(filenames);

    ">>>>>".writeln;
    //~ filenames.each!writeln;

    const batchSize = 1;

    static string[] mergeTwoChunks(string[] a, string[] b)
    {
        auto s = a~b;
        return [mergeFewASTs(s)];
    }

    auto retChunks = taskPool.fold!mergeTwoChunks(
        initialASTs.chunks(batchSize)
    );

    "====".writeln;
    writeln(retChunks);

    bool wasIgnoredFile;

    return wasIgnoredFile ? 3 : 0;
}

import std.process;

immutable clangBinary = "clang-19";

string createAST(string filename)
{
    const ret_filename = filename~".ast";

    // clang -cc1 -emit-pch -o main.ast main.c
    // clang -cc1 -emit-pch -o bar.ast bar.c
    // clang-19 -fsyntax-only -ferror-limit=1 --target=riscv32 -Xclang -emit-pch test3.c -Xclang -o -Xclang test3.c.ast
    auto cmdLine = [
        clangBinary,
        "-fsyntax-only",
        "-ferror-limit=1",
        "--target=riscv32", // base type sizes is not defined in preprocessed files
        "-Xclang", "-emit-pch",
        "-Xclang", "-o", "-Xclang" , ret_filename,
        filename,
    ];

/+
    auto cmdLine = [
        clangBinary,
        "-emit-ast",
        "-ferror-limit=1",
        "--target=riscv32", // base type sizes is not defined in preprocessed files
        //~ "-o", "/dev/null",
        //~ "-Xclang",
        //~ "-emit-pch",
        "-o", ret_filename,
        filename,
    ];
+/
    "Create AST".writeln;
    cmdLine.join(" ").writeln;

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during processing file "~filename, r[1]);

    return ret_filename;
}

string mergeFewASTs(R)(ref R fileNames)
{
    writeln("BEGIN MERGE OF: ", fileNames);

    //TODO: remove files if done

    size_t uniqNum;
    uniqNum++;

    const ret_filename = "/tmp/remove_me_"~uniqNum.to!string~".ast";
    const astMergeArgs = fileNames.map!(f => ["-Xclang", "-ast-merge", "-Xclang", f]).join.array;

    // clang-19 -fsyntax-only -ferror-limit=1 --target=riscv32 -Xclang -emit-pch -Xclang -o -Xclang test888.ast -Xclang -ast-merge -Xclang test3.c.ast /dev/null

    auto cmdLine = [
        clangBinary,
        "-fsyntax-only",
        "-ferror-limit=1",
        "--target=riscv32", // base type sizes is not defined in preprocessed files
        "-Xclang" , "-emit-pch",
        "-Xclang" , "-o", "-Xclang", ret_filename,
    ]~astMergeArgs~[
        "/dev/null"
    ];

/+
    auto cmdLine =
        [clangBinary, "-cc1"]
        ~astMergeArgs
        ~["-emit-pch", "-o", outfilename, "/dev/null"];
+/

    "Merge AST".writeln;
    cmdLine.join(" ").writeln;

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during merging AST processing files "~fileNames.to!string, r[1]);

    writeln("MERGED: ", fileNames);

    return ret_filename;
}
