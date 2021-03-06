function difference(x::VersionNumber, y::VersionNumber)
    if y.major > x.major
        return VersionNumber(y.major - x.major, y.minor, y.patch)
    elseif y.minor > x.minor
        return VersionNumber(y.major - x.major, y.minor - x.minor, y.patch)
    elseif y.patch > x.patch
        return VersionNumber(y.major - x.major, y.minor - x.minor, y.patch - x.patch)
    else
        throw(ArgumentError("first argument must be strictly less than the second argument"))
    end
end

function leftmost_nonzero(v::VersionNumber)::Symbol
    if v.major != 0
        return :major
    elseif v.minor != 0
        return :minor
    elseif v.patch != 0
        return :patch
    else
        throw(ArgumentError("there are no nonzero components"))
    end
end

function is_breaking(a::VersionNumber, b::VersionNumber)::Bool
    if a < b
        a_leftmost_nonzero = leftmost_nonzero(a)
        if a_leftmost_nonzero == :major
            if a.major == b.major
                return false # major stayed the same nonzero value => nonbreaking
            else
                return true # major increased => breaking
            end
        elseif a_leftmost_nonzero == :minor
            if a.major == b.major
                if a.minor == b.minor
                    return false # major stayed 0, minor stayed the same nonzero value, patch increased => nonbreaking
                else
                    return true  # major stayed 0 and minor increased => breaking
                end
            else
                return true # major increased => breaking
            end
        else
            always_assert(a_leftmost_nonzero == :patch)
            if a.major == b.major
                if a.minor == b.minor
                    # this corresponds to 0.0.1 -> 0.0.2
                    # set it to true if 0.0.1 -> 0.0.2 should be breaking
                    # set it to false if 0.0.1 -> 0.0.2 should be non-breaking
                    return true # major stayed 0, minor stayed 0, patch increased
                else
                    return true # major stayed 0 and minor increased => breaking
                end
            else
                return true # major increased => breaking
            end
        end
    else
        throw(ArgumentError("first argument must be strictly less than the second argument"))
    end
end

function latest_version(pkg::String, registry_path::String)
    all_versions = VersionNumber.(keys(Pkg.TOML.parsefile(joinpath(registry_path, uppercase(pkg[1:1]), pkg, "Versions.toml"))))
    return maximum(all_versions)
end

function julia_compat(pkg::String, version::VersionNumber, registry_path::String)
    all_compat_entries_for_julia = Vector{Pkg.Types.VersionRange}(undef, 0)
    compat = Pkg.TOML.parsefile(joinpath(registry_path, uppercase(pkg[1:1]), pkg, "Compat.toml"))
    for version_range in keys(compat)
        if version in Pkg.Types.VersionRange(version_range)
            for compat_entry in compat[version_range]
                name = compat_entry[1]
                if strip(lowercase(name)) == strip(lowercase("julia"))
                    value = compat_entry[2]
                    if value isa Vector
                        for x in value
                            x_range = Pkg.Types.VersionRange(x)
                            push!(all_compat_entries_for_julia, x_range)
                        end
                    else
                        value_range = Pkg.Types.VersionRange(value)
                        push!(all_compat_entries_for_julia, value_range)
                    end
                end
            end
        end
    end
    if length(all_compat_entries_for_julia) < 1
        return Pkg.Types.VersionRange[Pkg.Types.VersionRange("* - *")]
    else
        return all_compat_entries_for_julia
    end
end

function _has_upper_bound(r::Pkg.Types.VersionRange)
    return r.upper != Pkg.Types.VersionBound("*")
end

function range_did_not_narrow(r1::Pkg.Types.VersionRange, r2::Pkg.Types.VersionRange)
    result = !Pkg.Types.isless_ll(r1.lower, r2.lower) && !Pkg.Types.isless_uu(r2.upper, r1.upper)
    return result
end

function range_did_not_narrow(v1::Vector{Pkg.Types.VersionRange}, v2::Vector{Pkg.Types.VersionRange})
    @debug("", v1, v2, repr(v1), repr(v2))
    if isempty(v1) || isempty(v2)
        return false
    else
        n_1 = length(v1)
        n_2 = length(v2)
        results = falses(n_1, n_2) # v1 along the rows, v2 along the columns
        for i = 1:n_1
            for j = 1:n_2
                results[i, j] = range_did_not_narrow(v1[i], v2[j])
            end
        end
        @debug("", results, repr(results))
        return all(results)
    end
end
