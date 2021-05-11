"""
    run([env, cicfg::CIService]; kwargs...)

Run the `RegistryCI.AutoMerge` service.

# Arguments

- `env`:
- `ciccfg`:

# Keyword Arguments

- `merge_new_packages`:
- `merge_new_versions`:
- `new_package_waiting_period`: new package waiting period, e.g `Day(3)`.
- `new_jll_package_waiting_period`: new JLL package waiting period, e.g `Minute(20)`.
- `new_version_waiting_period`: new package version waiting period, e.g `Minute(10)`.
- `new_jll_version_waiting_period`: new JLL package version waiting period, e.g `Minute(10)`.
- `registry`: the registry name you want to run AutoMerge on.
- `tagbot_enabled`: if tagbot is enabled.
- `authorized_authors`: list of who can submit registration, e.g `String["JuliaRegistrator"]`.
- `authorized_authors_special_jll_exceptions`:
- `additional_statuses`:
- `additional_check_runs`:
- `error_exit_if_automerge_not_applicable`:
- `master_branch`: name of `master_branch`, e.g you may want to specify this to `"main"` for new GitHub repositories.
- `master_branch_is_default_branch`: if `master_branch` specified above is the default branch.
- `suggest_onepointzero`:
- `registry_deps`: list of registry dependencies, e.g your packages may depend on `General`.
- `api_url`: the registry host API URL, default is `"https://api.github.com"`.
- `check_license`: check package has a valid license, default is `false`.
- `public_registries`: list of public registries that you would want to avoid
dependency confusion (packages with same UUID).
- `read_only`: run in read only mode, default is `false`.

# Example

Here is an example of how `General` registry is configured

```julia
using RegistryCI
using Dates

RegistryCI.AutoMerge.run(
    merge_new_packages = ENV["MERGE_NEW_PACKAGES"] == "true",
    merge_new_versions = ENV["MERGE_NEW_VERSIONS"] == "true",
    new_package_waiting_period = Day(3),
    new_jll_package_waiting_period = Minute(20),
    new_version_waiting_period = Minute(10),
    new_jll_version_waiting_period = Minute(10),
    registry = "JuliaLang/General",
    tagbot_enabled = true,
    authorized_authors = String["JuliaRegistrator"],
    authorized_authors_special_jll_exceptions = String["jlbuild"],
    suggest_onepointzero = false,
    additional_statuses = String[],
    additional_check_runs = String[],
    check_license = true,
    public_registries = String["https://github.com/HolyLab/HolyLabRegistry"],
)
```
"""
function run(env = ENV,
             cicfg::CIService=auto_detect_ci_service(;env=env);
             merge_new_packages::Bool,
             merge_new_versions::Bool,
             new_package_waiting_period,
             new_jll_package_waiting_period,
             new_version_waiting_period,
             new_jll_version_waiting_period,
             registry::String,
             #
             tagbot_enabled::Bool=false,
             #
             authorized_authors::Vector{String},
             authorized_authors_special_jll_exceptions::Vector{String},
             #
             additional_statuses::AbstractVector{<:AbstractString} = String[],
             additional_check_runs::AbstractVector{<:AbstractString} = String[],
             #
             error_exit_if_automerge_not_applicable::Bool = false,
             #
             master_branch::String = "master",
             master_branch_is_default_branch::Bool = true,
             suggest_onepointzero::Bool = true,
             #
             registry_deps::Vector{<:AbstractString} = String[],
             api_url::String="https://api.github.com",
             check_license::Bool=false,
             # A list of public Julia registries (repository URLs)
             # which will be checked for UUID collisions in order to
             # mitigate the dependency confusion vulnerability. See
             # the `dependency_confusion.jl` file for details.
             public_registries::Vector{<:AbstractString} = String[],
             read_only::Bool=false)::Nothing
    all_statuses = deepcopy(additional_statuses)
    all_check_runs = deepcopy(additional_check_runs)
    push!(all_statuses, "automerge/decision")
    unique!(all_statuses)
    unique!(all_check_runs)
    api = GitHub.GitHubWebAPI(HTTP.URI(api_url))

    registry_head = directory_of_cloned_registry(cicfg; env=env)

    # Figure out what type of build this is
    run_pr_build = conditions_met_for_pr_build(cicfg; env=env, master_branch=master_branch)
    run_merge_build = conditions_met_for_merge_build(cicfg; env=env, master_branch=master_branch)

    if !(run_pr_build || run_merge_build)
        throw_not_automerge_applicable(
            AutoMergeWrongBuildType,
            "Build not determined to be either a PR build or a merge build. Exiting.";
            error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    # Authentication
    key = run_pr_build || !tagbot_enabled ? "AUTOMERGE_GITHUB_TOKEN" : "AUTOMERGE_TAGBOT_TOKEN"
    auth = my_retry(() -> GitHub.authenticate(api, env[key]))
    whoami = my_retry(() -> username(api, cicfg; auth=auth))
    @info("Authenticated to GitHub as \"$(whoami)\"")
    registry_repo = my_retry(() -> GitHub.repo(api, registry; auth=auth))

    if run_pr_build
        pr_number = pull_request_number(cicfg; env=env)
        pr_head_commit_sha = current_pr_head_commit_sha(cicfg; env=env)
        pull_request_build(api,
                           pr_number,
                           pr_head_commit_sha,
                           registry_repo,
                           registry_head;
                           auth = auth,
                           authorized_authors = authorized_authors,
                           authorized_authors_special_jll_exceptions = authorized_authors_special_jll_exceptions,
                           error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable,
                           master_branch = master_branch,
                           master_branch_is_default_branch = master_branch_is_default_branch,
                           suggest_onepointzero = suggest_onepointzero,
                           whoami = whoami,
                           registry_deps = registry_deps,
                           check_license = check_license,
                           public_registries = public_registries,
                           read_only = read_only)
    else
        always_assert(run_merge_build)
        cron_or_api_build(api,
                          registry_repo;
                          auth = auth,
                          authorized_authors = authorized_authors,
                          authorized_authors_special_jll_exceptions = authorized_authors_special_jll_exceptions,
                          merge_new_packages = merge_new_packages,
                          merge_new_versions = merge_new_versions,
                          new_package_waiting_period = new_package_waiting_period,
                          new_jll_package_waiting_period = new_jll_package_waiting_period,
                          new_version_waiting_period = new_version_waiting_period,
                          new_jll_version_waiting_period = new_jll_version_waiting_period,
                          whoami = whoami,
                          all_statuses = all_statuses,
                          all_check_runs = all_check_runs,
                          read_only = read_only)
    end
    return nothing
end
