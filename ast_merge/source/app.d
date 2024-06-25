import std.algorithm;
import std.conv: to;
import std.string: chomp;
import std.range;
import std.stdio;

struct CliOptions
{
    string out_file;
    string[] include_files;
    string[] clang_opts;
    size_t batch_size = 1;
    uint threads = 1;
}

CliOptions options;

int main(string[] args)
{
    import std.getopt;

    {
        //TODO: add option for files splitten by zero byte
        auto helpInformation = getopt(args,
            "output", `Output file`, &options.out_file,
            "include", `Additional include files`, &options.include_files,
            "clang_opts", `Clang options`, &options.clang_opts,
            "batch_size", `batch_size`, &options.batch_size,
            "threads", `threads`, &options.threads,
        );

        if(options.out_file == "")
        {
            stderr.writeln("Output file not specified");
            helpInformation.helpWanted = true;
        }

        if (helpInformation.helpWanted)
        {
            defaultGetoptPrinter(`Usage: `~args[0]~" [PARAMETER]...\n"~
                `Takes a list of AST files from STDIN and returns merged preprocessed file`,
                helpInformation.options);

            return 0;
        }
    }

    import std.file: write;

    write(options.out_file, ""); // to ensure that file can be created

    import std.parallelism;

    defaultPoolThreads(options.threads);

    const filenames = stdin.byLineCopy.array; //TODO: use asyncBuf?

    import clang_related;

    const includes = options.include_files.map!(a => ["-include", a]).join.array;

    auto units = filenames.map!(a => parseFile(a, options.clang_opts ~ includes));

    import clang;

    units
        .map!(a => a.cursor)
        .map!(a => a.children)
        .joiner
        //~ .filter!(a => a.isCanonical)
        //TODO: add .isFileScope filter?

        //~ .map!(a => a.displayName)
        //~ .each!writeln;

        .each!checkAndAdd;

        //~ .map!(a => a.spelling)
        //~ .each!writeln;

    "======".writeln;

    //~ addedDecls.byValue.each!(a => writeln(a, "\n   <<<<<<<<<<<<\n"));
    //~ addedDecls.byValue.map!(a => a.cur.getPrettyPrinted).each!(a => writeln(a, "\n   ===***===\n"));

    addedDecls.byKey.
        map!(a => addedDecls[a])
        .each!(
            a => a.isExcluded ? stderr.writeln(a.errMsg) : stdout.writeln(a.cur.getPrettyPrinted)
        );

    return 0;
}

import std.process;

immutable clangBinary = "clang-19";

immutable string[] clangArgsBase = [
        clangBinary,
        "-cc1",
        "-ferror-limit", "1",
        "-triple", "riscv32", // base type sizes is not defined in preprocessed files
        "/dev/null", // input code file disabled
        "-o", // next should be ret_filename
];

string createAST(string filename)
{
    const ret_filename = filename~".ast";

    const includes = options.include_files.map!(a => ["-include", a]).join.array;

    auto cmdLine =
        clangArgsBase
        ~ret_filename
        ~"-emit-pch"
        ~includes
        ~filename;

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during processing file "~filename, r[1]);

    return ret_filename;
}

string mergeFewASTs(string[] fileNames, const string prettyPrintedFile = null)
{
    import core.atomic;
    import core.thread.osthread: getpid;
    import std.file: remove;

    shared static size_t batchNum;
    const size_t currBatchNum = batchNum.atomicOp!"+="(1);

    shared static size_t fileNum;
    const size_t currFileNum = fileNum.atomicOp!"+="(fileNames.length);

    const ret_filename = prettyPrintedFile
        ? prettyPrintedFile
        : "/tmp/remove_me_"~getpid.to!string~"_"~currBatchNum.to!string~".ast";

    const astMergeArgs = fileNames.map!(f => ["-ast-merge", f]).join.array;

    auto cmdLine =
        clangArgsBase
        ~ret_filename
        ~(prettyPrintedFile is null ? "-emit-pch" : "-ast-print")
        ~ astMergeArgs;

    writeln("Merge AST batch #", currBatchNum);
    cmdLine.join(" ").writeln;

    auto r = execute(args: cmdLine);

    if(r[0] != 0)
        throw new Exception("error during merging AST processing files "~fileNames.to!string, r[1]);

    fileNames.each!remove;

    writeln("MERGED batch #", currBatchNum, ", total ", currFileNum.to!string, " files done");

    return ret_filename;
}
