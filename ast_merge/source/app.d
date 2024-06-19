import std.algorithm;
import std.conv: to;
import std.string: chomp;
import std.range;
import std.stdio;

struct CliOptions
{
    size_t batch_size = 1;
    uint threads = 1;
}

int main(string[] args)
{
    import std.getopt;

    CliOptions options;

    {
        //TODO: replace by option for files splitten by zero byte
        auto helpInformation = getopt(args,
            "batch_size", `batch_size`, &options.batch_size,
            "threads", `threads`, &options.threads,
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

    defaultPoolThreads(options.threads);

    const filenames = stdin.byLineCopy.array; //TODO: use asyncBuf
    auto initialASTs = taskPool.amap!createAST(filenames);

    //~ ">>>>>".writeln;
    //~ filenames.each!writeln;

    static string[] mergeTwoChunks(string[] a, string[] b)
    {
        auto s = a~b;
        return [mergeFewASTs(s)];
    }

    //~ auto retChunks = initialASTs
        //~ .chunks(batchSize)
        //~ .fold!mergeTwoChunks
        //~ .mergeFewASTs();

    auto retChunks = taskPool.fold!mergeTwoChunks(
        initialASTs.chunks(options.batch_size)
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
        "/dev/null", // input code file disabled
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
    if(fileNames.length == 1)
        return fileNames[0]; // skip latest bogus run

    import core.atomic;

    shared static size_t batchNum;
    const size_t currBatchNum = batchNum.atomicOp!"+="(1);

    shared static size_t fileNum;
    const size_t currFileNum = fileNum.atomicOp!"+="(fileNames.length);

    const ret_filename = "/tmp/remove_me_"~currBatchNum.to!string~".ast";
    const astMergeArgs = fileNames.map!(f => ["-ast-merge", f]).join.array;

    auto cmdLine = clangArgsBase ~ ret_filename ~ astMergeArgs;

    writeln("Merge AST batch #", currBatchNum);
    cmdLine.join(" ").writeln;

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during merging AST processing files "~fileNames.to!string, r[1]);

    import std.file;
    fileNames.each!remove;

    writeln("MERGED batch #", currBatchNum, ", total ", currFileNum.to!string, " files done");

    return ret_filename;
}
