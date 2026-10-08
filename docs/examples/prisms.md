# Enum cases and partial access

An enum case is available only when the source has that case. A read must
therefore account for both a match and a miss.

The following declarations are used throughout this page:

```cangjie
import lucida.*
import lucida.macrodsl.*

@DeriveOptics
public struct FileInfo {
    public FileInfo(public let name: String, public let size: Int64) {}
}

@DeriveOptics
public enum Entry {
    | Missing
    | File(FileInfo)
}
```

## Read a case

Inside a function:

```cangjie
let entry = Entry.File(FileInfo("notes.txt", 120))
let info = @f(entry?.File)
let name = @f(entry?.File.name)
```

`info` is `Option<FileInfo>` and `name` is `Option<String>`. Both reads
succeed for this value. If `entry` were `Entry.Missing`, both would return
`None`.

Use `?.File` for the case and `.name` for the payload's ordinary field.
The partial result belongs to the whole read; you do not insert another
`?.` before every subsequent field.

## Update a matching case

```cangjie
let renamed = @f(entry?.File.name <- "draft.txt")
let missing = Entry.Missing
let unchanged = @f(missing?.File.name <- "draft.txt")
```

`renamed` is `Entry.File(FileInfo("draft.txt", 120))`.
`unchanged` is still `Entry.Missing`. Both results have type `Entry`.

Derived case optics have type `Affine<Entry, FileInfo>` when kept as values:

```cangjie
let file = @f(@ty(Entry)?.File)
let updated = file.update(entry, FileInfo("draft.txt", 140))
let stillMissing = file.update(missing, FileInfo("draft.txt", 140))
```

An affine update takes the source so it can preserve an unmatched case.

## A prism also provides construction

A prism's backward operation is named `build`. It constructs a source from
a focus without consulting an existing source:

```cangjie
let file = Prism<Entry, FileInfo>(
    { entry: Entry =>
        match (entry) {
            case File(info) => Some(info)
            case Missing => Option<FileInfo>.None
        }
    },
    { info: FileInfo => Entry.File(info) }
)
```

`file.preview(entry)` tries to read a file. `file.build(info)` always
constructs an `Entry.File`. There is no old entry to preserve in that call.
This is the distinction between the `Prism` and `Affine` APIs.

For an update that should preserve other cases, use the derived case optic
or a partial DSL update. Do not substitute `build` for a guarded update.

## Other enum payload shapes

`@DeriveOptics` also handles cases with no payload and with several payloads:

```cangjie
@DeriveOptics
public enum ResultInfo {
    | Pending
    | Done(String, Int64)
}
```

`@f(result?.Pending)` returns `Option<Unit>`. `@f(result?.Done)` returns
`Option<(String, Int64)>`. Update the `Done` payload with a tuple of the same
shape, or continue into its elements using `._0` and `._1`.

The [derivation reference](deriving.md) explains these shapes. The
[composition reference](../api/composition.md) explains how a partial slot
affects the kind of a longer path.
