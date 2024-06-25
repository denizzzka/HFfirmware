module storage;

import clang_related;
import std.typecons;

struct Storage
{
    alias StorElem = Tuple!(Key, "key", CursorDescr, "descr");

    private StorElem[] addedDecls;
    private StorElem*[Key] index;

    void addCursor(Key key, CursorDescr d)
    {
        addedDecls ~= StorElem(key, d);
        index[key] = &addedDecls[$-1];
    }

    StorElem** findCursor(Key key)
    {
        return (key in index);
    }

    auto getSortedDecls()
    {
        import std.range: assumeSorted;

        return addedDecls; //.assumeSorted;
    }
}
