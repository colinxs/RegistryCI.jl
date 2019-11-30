function pull_request_build(::NewVersion,
                            pr::GitHub.PullRequest,
                            current_pr_head_commit_sha::String,
                            registry::GitHub.Repo;
                            auth::GitHub.Authorization,
                            authorized_authors::Vector{String},
                            registry_head::String,
                            registry_master::String,
                            suggest_onepointzero::Bool,
                            whoami::String)
    # first check if authorized author - if not, then quit
    # then check rules 1-3. if fail, post comment.
    # then check rules 4-5. if fail, post comment.
    # if everything passed, merge the pull request now
    # 1. Sequential version number - if the last version was 1.2.3 then the next can be 1.2.4, 1.3.0 or 2.0.0
    # 2. Compat for all dependencies - all [deps] should also have [compat] entries (and Julia itself) - [compat] entries should have upper bounds
    # 3. If it is a patch release, then it does not narrow the Julia compat range
    # 4. Version can be installed - given the proposed changes to the registry, can we resolve and install the new version of the package?
    # 5. Version can be loaded - once it's been installed (and built?), can we load the code?
    pkg, version = parse_pull_request_title(NewVersion(), pr)
    @info("This is a new version pull request", pkg, version)
    pr_author_login = author_login(pr)
    if is_open(pr)
        if pr_author_login in authorized_authors
            my_retry(() -> delete_all_of_my_reviews!(registry, pr; auth = auth, whoami = whoami))
            @info "HERE" registry current_pr_head_commit_sha, auth
            my_retry(() -> GitHub.create_status(registry, current_pr_head_commit_sha; auth=auth, params=Dict("state" => "pending", "context" => "automerge/decision", "description" => "New version. Pending.")))
            @info "THERE"
            g0, m0 = pr_only_changes_allowed_files(NewVersion(), registry, pr, pkg; auth = auth)
            newv_g1, newv_m1, release_type = meets_sequential_version_number(pkg,
                                                                             version;
                                                                             registry_head = registry_head,
                                                                             registry_master = registry_master)
            newv_g2, newv_m2 = meets_compat_for_all_deps(registry_head,
                                                         pkg,
                                                         version)
            if release_type == :patch
                newv_g3, newv_m3 = meets_patch_release_does_not_narrow_julia_compat(pkg,
                                                                                    version;
                                                                                    registry_head = registry_head,
                                                                                    registry_master = registry_master)
            else
                newv_g3 = true
                newv_m3 = ""
            end
            newv_g1through3 = [g0, newv_g1, newv_g2, newv_g3]
            @info("Only modifies the files that it's allowed to modify", meets_this_guideline = g0, message = m0)
            @info("Sequential version number", meets_this_guideline = newv_g1, message = newv_m1)
            @info("Compat (with upper bound) for all dependencies", meets_this_guideline = newv_g2, message = newv_m2)
            @info("If it is a patch release, then it does not narrow the Julia compat range", meets_this_guideline = newv_g3, message = newv_m3)
            if all(newv_g1through3)
                newv_g4and5, newv_m4and5 = meets_version_can_be_loaded(registry_head,
                                                                       pkg,
                                                                       version)
                @info("Version can be installed and loaded", meets_this_guideline = newv_g4and5, message = newv_m4and5)
                if newv_g4and5
                    newv_commenttextpass = comment_text_pass(NewVersion(),
                                                             suggest_onepointzero,
                                                             version)
                    my_retry(() -> delete_all_of_my_reviews!(registry, pr; auth = auth, whoami = whoami))
                    my_retry(() -> approve!(registry, pr, current_pr_head_commit_sha; auth = auth, body = newv_commenttextpass, whoami = whoami))
                    my_retry(() -> GitHub.create_status(registry, current_pr_head_commit_sha; auth=auth, params=Dict("state" => "success", "context" => "automerge/decision", "description" => "New version. Approved. sha=\"$(current_pr_head_commit_sha)\"")))
                    return nothing
                else
                    newv_commenttext4and5 = comment_text_fail(NewVersion(),
                                                              [newv_m4and5],
                                                              suggest_onepointzero,
                                                              version)
                    my_retry(() -> post_comment!(registry, pr, newv_commenttext4and5; auth = auth))
                    my_retry(() -> GitHub.create_status(registry, current_pr_head_commit_sha; auth=auth, params=Dict("state" => "failure", "context" => "automerge/decision", "description" => "New version. Failed.")))
                    error("The automerge guidelines were not met.")
                    return nothing
                end
            else
                newv_allmessages1through3 = [m0, newv_m1, newv_m2, newv_m3]
                newv_failingmessages1through3 = newv_allmessages1through3[.!newv_g1through3]
                newv_commenttext1through3 = comment_text_fail(NewVersion(),
                                                              newv_failingmessages1through3,
                                                              suggest_onepointzero,
                                                              version)
                my_retry(() -> post_comment!(registry, pr, newv_commenttext1through3; auth = auth))
                my_retry(() -> GitHub.create_status(registry, current_pr_head_commit_sha; auth=auth, params=Dict("state" => "failure", "context" => "automerge/decision", "description" => "New version. Failed.")))
                error("The automerge guidelines were not met.")
                return nothing
            end
        else
            @info("Author $(pr_author_login) is not authorized to automerge. Exiting...")
            return nothing
        end
    else
        @info("The pull request is not open. Exiting...")
        return nothing
    end
    return nothing
end
