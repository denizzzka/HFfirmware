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

    //~ ">>>>>".writeln;
    //~ filenames.each!writeln;

    static string[] mergeTwoChunks(string[] a, string[] b)
    {
        auto s = a~b;
        return [mergeFewASTs(s)];
    }

    const batchSize = 50;

    //~ auto retChunks = initialASTs
        //~ .chunks(batchSize)
        //~ .fold!mergeTwoChunks
        //~ .mergeFewASTs();

    auto retChunks = taskPool.fold!mergeTwoChunks(
        initialASTs.chunks(batchSize)
    ).mergeFewASTs();

    "====".writeln;
    retChunks.writeln;

    bool wasIgnoredFile;

    return wasIgnoredFile ? 3 : 0;
}

import std.process;

immutable clangBinary = "clang-19";

immutable string[] clangArgsBase = [
        clangBinary,
        "-cc1",
        "-ferror-limit", "1",
        "-triple", "riscv32", // base type sizes is not defined in preprocessed files
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

string mergeFewASTs(string[] fileNames)
{
    import core.atomic;

    shared static size_t batchNum;
    const size_t currBatchNum = batchNum.atomicOp!"+="(1);

    shared static size_t fileNum;
    const size_t currFileNum = fileNum.atomicOp!"+="(fileNames.length);

    const ret_filename = "/tmp/remove_me_"~currBatchNum.to!string~".ast";
    const astMergeArgs = fileNames.map!(f => ["-ast-merge", f]).join.array;

    auto cmdLine = clangArgsBase ~ ret_filename ~ astMergeArgs;

    "Merge AST".writeln;
    cmdLine.join(" ").writeln;

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during merging AST processing files "~fileNames.to!string, r[1]);

    import std.file;
    fileNames.each!remove;

    writeln("(", currFileNum.to!string, " done) MERGED: ", fileNames);

    return ret_filename;
}
