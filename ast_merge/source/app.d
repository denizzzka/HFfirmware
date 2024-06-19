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
    filenames.each!writeln;

    const batchSize = 3;

    //~ auto ret = taskPool.fold!((a, b) => (a~b).mergeFewASTs)(
        //~ initialASTs.chunks(batchSize)
    //~ );

    static string[] mergeChunks(string[] a, string[] b) => a;

    auto retChunks = taskPool.fold!mergeChunks(
        initialASTs.chunks(batchSize)
    );

    static string mergeSingleAST(string a, string b) => a;

    auto ret = taskPool.fold!mergeSingleAST(retChunks);

    "====".writeln;
    //~ initialASTs.chunks(batchSize).each!writeln;
    writeln(ret);

    bool wasIgnoredFile;

    return wasIgnoredFile ? 3 : 0;
}

import std.process;

string createAST(string filename)
{
    const ret_filename = filename~".ast";

    auto cmdLine = [
        "clang",
        "-emit-ast",
        "-ferror-limit=1",
        "--target=riscv32", // base type sizes is not defined in preprocessed files
        "-o", ret_filename,
        filename,
    ];

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during processing file "~filename, r[1]);

    return ret_filename;
}

string mergeFewASTs(R)(ref R fileNames)
{
    //TODO: remove files if done

    // clang -cc1 -ast-merge test3.ast -ast-merge test3.ast /dev/null -emit-pch -o main.ast

    const outfilename = "/tmp/removeme.ast";
    const astMergeArgs = fileNames.map!(f => ["-ast-merge"].chain([f])).join;

    auto cmdLine =
        ["clang", "-cc1"]
        ~astMergeArgs
        ~["-emit-pch", "-o", outfilename, "/dev/null"];

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during merging AST processing files "~astRange.to!string, r[1]);

    return outfilename;
}
