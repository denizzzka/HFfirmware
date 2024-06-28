module main;

import std.algorithm;
import std.conv: to;
import std.string: chomp;
import std.range;
import std.stdio;

struct CliOptions
{
    enum ShowExcluded { no, brief, full, };
    static __gshared CliOptions* _this;

    string out_file;
    string[] include_files;
    string[] clang_opts;
    ShowExcluded show_excluded;
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
            "show_excluded", `Output excluded entries: no/brief/full`, &options.show_excluded,
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

        const string[] includes = options.include_files.map!(a => ["-include", a]).join.array;
        options.clang_opts ~= includes;

        CliOptions._this = &options;
    }

    import std.stdio: File;

    auto outFile = File(options.out_file, "w");

    import std.parallelism;

    defaultPoolThreads(options.threads);

    const filenames = stdin.byLineCopy.array; //TODO: use asyncBuf?

    import clang_related;
    import std.parallelism;

    static auto parseF(string filename) => parseFile(filename, CliOptions._this.clang_opts);

    auto units = taskPool.amap!parseF(filenames);

    import dpp.expansion;

    auto unitsCanonicalCursors = units.map!(a => a.canonicalCursors);

    import clang;
    import storage: Key;

    unitsCanonicalCursors
        .joiner
        .tee!(a => assert(a.isFileScope))
        .each!checkAndAdd;

    static void showExcluded(in Key key, in CursorDescr c, in CliOptions.ShowExcluded opt)
    {
        stderr.writeln(">>>>>>>>>>>>>>> Key: ", key);

        static string pretty(in Cursor c) => c.getSourceRange.fileLinePrettyString~"\t"~c.toString;

        if(opt == CliOptions.ShowExcluded.brief)
        {
            stderr.writeln(pretty(c.cur));

            c.alsoExcluded.each!(a => stderr.writeln(pretty(a.cur)));
        }
        else if(opt == CliOptions.ShowExcluded.full)
            c.alsoExcluded.each!(a => stderr.writeln(a.errMsg));
    }

    import std.typecons;

    auto statements = cStorage.getSortedDecls
        .filter!((a) {
            if(a.descr.isExcluded)
            {
                showExcluded(a.key, a.descr, options.show_excluded);
                return false;
            }
            else
                return true;
        })
        .map!(a => a.descr.cur);

    import dpp.runtime.context;
    import dpp.runtime.options: Options;

    auto dppOptions = Options();
    auto language = dpp.runtime.context.Language.C;
    auto context = Context(dppOptions, language);

    void addDContextData(ref Cursor cursor, string file = __FILE__, size_t line = __LINE__)
    {
        import dpp.translation.translation;

        const indentation = context.indentation;
        const lines = translateTopLevelCursor(cursor, context, file, line);
        if(lines.length) context.writeln(lines);
        context.setIndentation(indentation);
    }

    statements
        .each!(a => addDContextData(a));

    context.fixNames;

    outFile.writeln(context.translation);

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
