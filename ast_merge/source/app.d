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

immutable clangBinary = "clang-18";

immutable string[] clangArgsBase = [
        clangBinary,
        "-cc1",
        "-ferror-limit", "1",
        "-fsyntax-only",
        "-aux-target-cpu", "riscv32", // base type sizes is not defined in preprocessed files
        "-emit-pch",
        "-o", // next should be ret_filename
];

string createAST(string filename)
{
    const ret_filename = filename~".ast";

    auto cmdLine = clangArgsBase ~ [ret_filename, filename];

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during processing file "~filename, r[1]);

    return ret_filename;
}

string mergeFewASTs(R)(ref R fileNames)
{
    //TODO: remove files if done

    static size_t uniqNum;
    uniqNum++;

    const ret_filename = "/tmp/remove_me_"~uniqNum.to!string~".ast";
    const astMergeArgs = fileNames.map!(f => ["-ast-merge", f]).join.array;

    // clang-19 -fsyntax-only -ferror-limit=1 --target=riscv32 -Xclang -emit-pch -Xclang -o -Xclang test888.ast -Xclang -ast-merge -Xclang test3.c.ast /dev/null

    auto cmdLine = clangArgsBase ~ astMergeArgs ~ [ret_filename]; //, "/dev/null"];

    "Merge AST".writeln;
    cmdLine.join(" ").writeln;

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during merging AST processing files "~fileNames.to!string, r[1]);

    writeln("MERGED: ", fileNames);

    return ret_filename;
}
