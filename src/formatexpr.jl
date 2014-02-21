# formatting expression

### Format entry

immutable FormatEntry
    iarg::Int
    spec::FormatSpec

    FormatEntry(ia::Int, spec::FormatSpec) = new(ia, spec)
    FormatEntry(ia::Int, spec::String) = new(ia, FormatSpec(spec))
end


# pos > 0: must not have iarg in expression (use pos+1), return (entry, pos + 1)
# pos < 0: must have iarg in expression, return (entry, -1)
# pos = 0: init, can be either, return (entry, 1) or (entry, -1)
function make_formatentry(s::String, pos::Int)
    @assert s[1] == '{' && s[end] == '}'
    sc = s[2:end-1]
    icolon = search(sc, ':')
    if icolon == 0  # no colon
        iarg = isempty(sc) ? -1 : int(sc)
        spec = FormatSpec('s')
    else
        iarg = icolon >=2 ? int(sc[1:icolon-1]) : -1
        iarg != 0 || error("Argument index cannot be zero.")
        spec = FormatSpec(sc[icolon+1:end])
    end

    if pos > 0
        iarg < 0 || error("entry with and without argument index must not coexist.")
        iarg = (pos += 1)
    elseif pos < 0
        iarg > 0 || error("entry with and without argument index must not coexist.")
    else # pos == 0
        if iarg < 0
            iarg = pos = 1
        else
            pos = -1
        end
    end
    return (FormatEntry(iarg, spec), pos)
end


### Format expression

type FormatExpr
    prefix::UTF8String
    suffix::UTF8String
    entries::Vector{FormatEntry}
    inter::Vector{UTF8String}
end

_raise_unmatched_lbrace() = error("Unmatched { in format expression.")

function find_next_entry_open(s::String, si::Int)
    slen = length(s)
    p = search(s, '{', si)
    p < slen || _raise_unmatched_lbrace()
    while p > 0 && s[p+1] == '{'  # escape `{{`
        p = search(s, '{', p+2)
        p < slen || _raise_unmatched_lbrace()
    end
    # println("open at $p")
    pre = p > 0 ? s[si:p-1] : s[si:end]
    if !isempty(pre)
        pre = replace(pre, "{{", '{')
        pre = replace(pre, "}}", '}')
    end
    return (p, utf8(pre))
end

function find_next_entry_close(s::String, si::Int)
    slen = length(s)
    p = search(s, '}', si)
    p > 0 || _raise_unmatched_lbrace()
    # println("close at $p")
    return p
end

function FormatExpr(s::String)
    slen = length(s)
    
    # init
    prefix = utf8("")
    suffix = utf8("")
    entries = FormatEntry[]
    inter = UTF8String[]

    # scan
    (p, prefix) = find_next_entry_open(s, 1)
    if p > 0
        q = find_next_entry_close(s, p+1)
        (e, pos) = make_formatentry(s[p:q], 0)
        push!(entries, e)
        (p, pre) = find_next_entry_open(s, q+1)
        while p > 0
            push!(inter, pre)
            q = find_next_entry_close(s, p+1)
            (e, pos) = make_formatentry(s[p:q], pos)
            push!(entries, e)
            (p, pre) = find_next_entry_open(s, q+1)
        end
        suffix = pre
    end
    FormatExpr(prefix, suffix, entries, inter)
end

function printfmt(io::IO, fe::FormatExpr, args...)
    if !isempty(fe.prefix)
        write(io, fe.prefix)
    end
    ents = fe.entries
    ne = length(ents)
    if ne > 0
        e = ents[1]
        printfmt(io, e.spec, args[e.iarg])
        for i = 2:ne
            write(io, fe.inter[i-1])
            e = ents[i]
            printfmt(io, e.spec, args[e.iarg])
        end
    end
    if !isempty(fe.suffix)
        write(io, fe.suffix)
    end
end

printfmt(io::IO, fe::String, args...) = printfmt(io, FormatExpr(fe), args...)
printfmt(fe::Union(String,FormatExpr), args...) = printfmt(STDOUT, fe, args...)

printfmtln(io::IO, fe::Union(String,FormatExpr), args...) = (printfmt(io, fe, args...); println(io))
printfmtln(fe::Union(String,FormatExpr), args...) = printfmtln(STDOUT, fe, args...)

format(fe::Union(String,FormatExpr), args...) = 
    (buf = IOBuffer(); printfmt(buf, fe, args...); bytestring(buf))
