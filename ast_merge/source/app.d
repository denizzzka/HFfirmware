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

    import std.algorithm;
    import std.conv: to;
    import std.string: chomp;
    import std.range;
    import std.stdio;

    static string createAST(string filename)
    {
        import std.process;

        auto cmdLine = [
            "clang",
            "-emit-ast",
            "-ferror-limit=1",
            "--target=riscv32", // base type sizes is not defined in preprocessed files
            "-o", "/dev/stdout",
            filename,
        ];

        auto r = execute(args: cmdLine);

        if(r[0] != 0)
            throw new Exception("error during processing file "~filename, r[1]);

        writeln("cmd ", cmdLine, " done");

        return r[1];
    }

    const batchSize = 3;

    size_t tmpNum;

    auto initialASTs = stdin
        .byLineCopy // for reading from stdin only, for files can be used .byLine
        .map!(filename => createAST(filename));

    //~ auto optionsChains = stdin
        //~ .byLineCopy // for reading from stdin only, for files can be used .byLine
        //~ .chunks(batchSize)
        //~ .map!(
            //~ a => a.map!(f => ["-ast-merge"].chain([f])).join
        //~ )
        //~ .map!(a => exec(a));

    //~ optionsChains.each!writeln;
    initialASTs.each!writeln;

    bool wasIgnoredFile;

    return wasIgnoredFile ? 3 : 0;
}
