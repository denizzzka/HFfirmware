module clang_related;

import clang;
import storage;
import std.algorithm;
import std.array;
import std.conv: to;
import std.range;

TranslationUnit parseFile(string filename, in string[] args)
{
    enum flags =
          TranslationUnitFlags.SkipFunctionBodies
        | TranslationUnitFlags.IgnoreNonErrorsFromIncludedFiles
        | TranslationUnitFlags.KeepGoing; //Do not stop processing when fatal errors are encountered

    return parse(filename, args); //, flags);
}

Storage cStorage;

version(DebugOutput)  import std.stdio;

private bool[string][Cursor.Kind] ignoredDecls;

private void fillAA(Cursor.Kind kind, string[] names)
{
    import std.algorithm;

    bool[string] namesAA;
    names.each!(a => namesAA[a] = true);
    ignoredDecls[kind] = namesAA;
}

shared static this()
{
    with(Cursor.Kind)
    {
        fillAA(StaticAssert,    [""]);
        fillAA(TypedefDecl,     ["##ANY##"]); //FIXME: remove
        fillAA(FunctionDecl, //FIXME: remove
            [
                "esp_log_buffer_hex",
                "esp_log_buffer_char",
                "is_valid_host",
                "spi_intr",
                "xTimerCreateTimerTask",
                "lookup_cmd_handler",
                "efuse_ll_set_pgm_cmd",
                "read_delta_t_from_efuse", // one is from legacy module
                "esp_reset_reason_get_hint", // two different sections
                "esp_system_get_time", // TODO: one of them have "weak" attr and can be ommited automatically
                "_pmksa_cache_free_entry",
                "pmksa_cache_expire",
                "forced_memzero",
                "new_config",
                "convert_key_type",
                "get_array_item",
                "crypto_rng_wrapper",
                "http_dispatch_event_to_event_loop",
                "esp_system_get_time_resolution",
                "rtc_spinlock",
                "handle_session_command1",
                "wpa_parse_generic",
                "esp_reset_reason_set_hint",
                "prov_start",
                "set_config_service",
                //~ "delete_config",
            ]
        );
        fillAA(StructDecl,
            [
                "sigaction",
                "rsn_pmksa_cache_entry",
                "mbedtls_cipher_info_t",
                "wpa_eapol_ie_parse",
                "rsn_pmksa_cache",
                //~ "session",
            ]
        );
        fillAA(VarDecl,
            [
                "TAG",
                "SPI_TAG",
                "spihost",
                "s_platform",
                "cmd_table",
                "registered_heaps", // extern and usual struct declarations
                "default_router_list",
                "s_ctx",
                "prefix_list",
                "neighbor_cache",
                "chip_name",
                "destination_cache",
                "s_config",
                //~ "rtc_spinlock",
            ]
        );
    }

    ignoredDecls.rehash;
}

void checkAndAdd(ref Cursor cur)
{
    import std.algorithm.comparison: equal;

    version(DebugOutput) cur.underlyingType.writeln;

    Key key = {
        name: cur.spelling,
        kind: cur.kind,
        isDefinition: cur.isDefinition,
    };

    auto found = cStorage.findCursor(key);

    auto descr = CursorDescr(cur);

    if(found is null)
    {
        version(DebugOutput) writeln(cur, " not found");

        cStorage.addCursor(key, descr);
    }
    else
        cmpCursors(key, (*found).descr, descr);
}

private void cmpCursors(Key key, ref CursorDescr old_orig, ref CursorDescr new_orig)
{
    Cursor _old = old_orig.cur;
    const Cursor _new = new_orig.cur;

    const ignoreFuncArgsNames = (key.kind == Cursor.Kind.FunctionDecl && !key.isDefinition);

    const oldHash = _old.calcIndependentHash(ignoreFuncArgsNames);
    const newHash = _new.calcIndependentHash(ignoreFuncArgsNames);

    const succCmp = ignoreFuncArgsNames || (oldHash == newHash) || (_old.getPrettyPrinted == _new.getPrettyPrinted);

    if(!succCmp)
    {
        auto ignored = (key.kind in ignoredDecls);
        if(ignored !is null)
        {
            bool mathed =
                ((_old.spelling in *ignored) !is null) ||
                (("##ANY##" in *ignored) !is null);

            // we are on ignored cursor?
            if(mathed) return;
        }

        //~ deepCmpCursors(_old, _new);

        string errMsg;

        import main: CliOptions, options;

        if(options.show_excluded == CliOptions.ShowExcluded.full)
        {
            const osr = old_orig.cur.getSourceRange;
            const nsr = new_orig.cur.getSourceRange;

            errMsg = "New cursor is not equal to previously saved:\n"
                ~"Old: "~osr.fileLinePrettyString~"\n"
                ~old_orig.cur.getPrettyPrinted~"\n"
                ~"New: "~nsr.fileLinePrettyString~"\n"
                ~new_orig.cur.getPrettyPrinted~"\n"
                ~"Old orig cursor: "~old_orig.cur.toString~"\n"
                ~"New orig cursor: "~new_orig.cur.toString~"\n"
                ~"Hash old: "~oldHash.to!string~"\n"
                ~"Hash new: "~newHash.to!string;
        }

        old_orig.alsoExcluded ~= CursorDescr.AlsoExcluded(new_orig.cur, errMsg);
    }
}

struct CursorDescr
{
    static struct AlsoExcluded
    {
        Cursor cur;
        string errMsg;
    }

    Cursor cur;
    AlsoExcluded[] alsoExcluded;

    bool isExcluded() const => alsoExcluded !is null;
}

version(DebugOutput)
private auto deepCmpCursors(in Cursor c1, in Cursor c2)
{
    Cursor[] r1;
    Cursor[] r2;

    c1.visitRecursive((c, p) { r1 ~= c; });
    c2.visitRecursive((c, p) { r2 ~= c; });

    r1.each!(a => stderr.writeln(a));
    stderr.writeln("=====");
    r2.each!(a => stderr.writeln(a));
}

alias IndependentHash = ubyte[16];

private IndependentHash calcIndependentHash(in Cursor c, bool ignoreArgNames)
{
    import clang.c.index;
    import std.digest.murmurhash;
    import std.string;
    import std.stdio;

    MurmurHash3!(128, 64) acc;

    import std.stdio;
    //~ writeln("calh hash of ", c);

    void calcHash(in Cursor cur, in Cursor parent)
    {
    with(Cursor.Kind)
    {
        //~ writeln(cur);
        if(cur.kind == Cursor.Kind.ParmDecl && ignoreArgNames)
        {
            auto t = Type(cur.type);
            auto c = Cursor(c.kind, "", t);

            acc.put(c.toString.representation);
        }
        else if(cur.kind == Cursor.Kind.FirstAttr && parent.kind == Cursor.Kind.FunctionDecl)
        {
            // ignore function __attribute__ cursors
        }
        else
            acc.put(cur.toString.representation);
    }
    }

    calcHash(c, c);
    c.visitRecursive(&calcHash);

    return acc.finish();
}

string getPrettyPrinted(in Cursor cur)
{
    import clang.c.index;

    return cur.cx.clang_getCursorPrettyPrinted(null).toString;
}

auto getSourceRange(in Cursor c)
{
    import clang.c.index;

    //TODO: make libclang _sourceRangeCreate public

    return SourceRange(clang_getCursorExtent(c.cx));
}

string fileLinePrettyString(in SourceRange r)
{
    return r.path~":"~r.start.line.to!string~":"~r.start.column.to!string;
}

void visitRecursive(const ref Cursor cursor, scope void delegate(Cursor cursor, Cursor parent) visitor) @safe
{
    ChildVisitResult internalVisitor(Cursor c, Cursor parent)
    {
        visitor(c, parent);
        return ChildVisitResult.Recurse;
    }

    cursor.visitChildren(&internalVisitor);
}
