using DelimitedFiles
using YAML
using Logging
using Random

#-- main entry point
function main() 
    # Config file provided?
    if (size(ARGS,1)==0)
        # print usage
        println("Usage: julia TestDataGen.jl configFile.yaml")
        exit()
    end

    # Load Config
    configFile = ARGS[1]
    loadConfig(configFile)
    
    println("Matching v0.03. Running config " * config["name"]);
    
    loadPreferenceData()             # read the data
    
    # perfrom matching
    performMatching()

    # print the assignments
    printAssignments()
end
#-- end of main

#-- performs the matching
function performMatching()
    # initial assignment
    performIntialAssignments()

    # check for any switching
    performFavorableSwaps()
end
#-- end of perform Matching

#-- perform initial assignments
function performIntialAssignments()
    global prefs, assignments, mCount, gCount, mPerG

    # reset all assignments
    assignments = zeros(Int64, gCount, mPerG)

    # assign one random members to each group
    for (g,m) in enumerate(view(sortperm(rand(mCount)),1:gCount))
        assignments[g,1]=m
    end
    
    for assignLevel in 2:mPerG
        # so now the groups are set and will vote collectively on 
        # further members. This is similar to gale shapley
        # the member proposes to the group. The algorithm will be
        # member advantaged. We can also do group advantaged by 
        # flipping the roles

        # We are currently assigning assignLevel of each group
        
        # get the unassigned members in this round
        unassignedMembers = filter( m -> !(in(reshape(assignments,gCount*mPerG,1)).(m)), 1:mCount)

        # for each unassigned member generate preference list for each group once
        local  m2gPrefs = getMemberPrefForAllGroups(unassignedMembers);
        
        # for each group generate perference list for each member
        local  g2mPrefs = getGroupPrefForAllMembers(unassignedMembers)
        
        # now we have the preference orders for groups and members
        # we can get on to the proposal phase
        local rejectedBy = Array{Array{Int64,1},1}(undef,mCount)
        for m in unassignedMembers
            rejectedBy[m] = Array{Int64,1}(undef,0)
        end
        
        while (!isempty(unassignedMembers)) 
            # dequeue this member
            m = popfirst!(unassignedMembers)

            # in order of his preference
            for g in m2gPrefs[m,:]
                # skip group if rejected before
                in(rejectedBy[m]).(g) && continue

                # the member at this assign level in g
                m2 = assignments[g,assignLevel]
                
                if (m2 == 0)
                    # accept proposal
                    assignments[g,assignLevel] = m
                    break;
                elseif (g2mPrefs[g,m] > g2mPrefs[g,m2])
                    assignments[g,assignLevel] = m
                    # m2 is unassigned
                    push!(unassignedMembers,m2)
                    push!(rejectedBy[m2],g)
                    break;
                else 
                    # m is not better. Mark as rejected
                    push!(rejectedBy[m],g)
                end
            end
            # if by this time m is not assigned to group, 
            # he is not going to be assigned at this assign Level
        end

        # The assignLevel is complete. All groups should have their best pick
        # Lets check if there are any swaps we can make now
        performFavorableSwaps()
    end

    
end
#-- end of performInitialAssignments


#-- This function performs any swaps necessary to increase fit
function performFavorableSwaps()
    global mCount, gCount, assignments, prefs

    # build a member to g mapping
    #assignments = getSortedGroups()
    local memberGroups =  Array{Array{Int64,1},1}(undef,mCount)
    for (g,gms) in enumerate(eachrow(assignments))
        for (c,m) in enumerate(gms)
            m==0 && continue
            memberGroups[m] = [g,c]
        end
    end
    
    # only assigned members are switched
    local assignedMembers = reshape(assignments,gCount*mPerG,1)
    assignedMembers = filter( m -> m!=0, assignedMembers)

    #shuffle!(assignedMembers)
    switches = 1
    cycleCount = 0

    @show assignments
    @show memberGroups
    @show assignedMembers

    while switches>0
        cycleCount += 1
        @info "Beginning of Cycle $cycleCount"
        #printAssignments(false)

        #local rejectedBy = Array{Array{Int64,1},1}(undef,mCount)
        #for m in assignedMembers
        #    rejectedBy[m] = Array{Int64,1}(undef,0)
        #end
        #local tAssignedMembers = assignedMembers
        switches = 0
        stable = true
        bene = true
        
        #while !isempty(tAssignedMembers) # && switches<mCount*gCount/2
        #    m = popfirst!(tAssignedMembers)
        for m in assignedMembers
            for m2 in assignedMembers
                # same member
                m==m2 && continue
                
                gc  = memberGroups[m]
                gc2 = memberGroups[m2]
                    
                # m and m2 are in same group?
                (gc[1]==gc2[1]) && continue   
                
                gScore = averagePrefOfGroup(gc[1])
                g2Score =  averagePrefOfGroup(gc2[1])
                
                gScoreWithM2 = averagePrefOfGroup(gc[1],m2,m)
                g2ScoreWithM = averagePrefOfGroup(gc2[1], m, m2)
                
                # statbility condition check
                mPrefForG = memberPrefForGroup(m,gc[1])
                mPrefForG2 = memberPrefForGroup(m,gc2[1],m2)
                gPrefForM = groupPrefForMember(m,gc2[1],m2)
                gPrefForM2 = groupPrefForMember(m2,gc2[1],m2)
                println("- $m\t$m2\t$gScore\t$g2Score\t$gScoreWithM2\t$g2ScoreWithM")
                if ((mPrefForG < mPrefForG2 && gPrefForM2 < gPrefForM))
                    println("-- Unstable $m($(gc[1])) $m2($(gc2[1]))")
                    println("-- m$m prefs  $mPrefForG $mPrefForG2 ")
                    println("-- g$(gc2[1])'s prefs $gPrefForM $gPrefForM2")
                    stable = false
                end
                
                #if (mPrefForG < mPrefForG2 && gPrefForM2<gPrefForM)  
                if (gScore + g2Score < g2ScoreWithM + gScoreWithM2)  
                #if (gScore + g2Score < g2ScoreWithM + gScoreWithM2) || (mPrefForG < mPrefForG2 && gPrefForM2<gPrefForM)  
                    #println("---- BEFORE Switching $m $m2")
                    #@show assignments
                    #@show(gScore, g2Score, gScoreWithM2, g2ScoreWithM)
                    
                    #@show gc
                    #@show gc2
                    
                    # switch is better
                    assignments[gc[1], gc[2] ] = m2
                    assignments[gc2[1],gc2[2]] = m
                    memberGroups[m]  = gc2
                    memberGroups[m2] = gc

                    #if (!in(tAssignedMembers).(m2)) 
                    #    push!(tAssignedMembers,m2)
                    #end

                    switches += 1
                    
                    #println("---- AFTER ")
                    #@show assignments
                #elseif (gScore + g2Score < g2ScoreWithM + gScoreWithM2)
                #    bene = false
                end
            end
        end

        println("Enf of Cycle $cycleCount Switches = $switches Stable = $stable / $bene")
        #printAssignments(false)

    end
end
#-- end of function perform favorable swaps


#-- prints the assignments
function printAssignments(sortAssignments=true) 
    global mCount, gCount, assignments

    local tAssignments = sortAssignments ? getSortedGroups() : assignments
    
    for (i,gm) in enumerate(eachrow(tAssignments))
        print(lpad(i,2," ") * ": ")
        for m in gm
            print(lpad(m,4," "))
        end
        println()
    end
    print("Score: ");
    println(averagePrefOfGroups());

end
#-- end of print Assignment

#-- Sorts the groups and returns sorted assignments
#-- Should be careful when doing it on global
#-- the function itself has no side effects
function getSortedGroups()
    global mCount, gCount, assignments
    local tAssignments = zeros(Int64,gCount, mPerG)
    for g=1:gCount
        tAssignments[g,:] = sort(assignments[g,:], by=x-> x==0 ? mCount+1 : x)
    end
    tAssignments = tAssignments[sortperm(tAssignments[:, 1]), :]
    return tAssignments
end
#-- end of sort Groups


#-- helper. Generates each unassigned member preference for all groups
function getMemberPrefForAllGroups(unassignedMembers)
    local gMemberPrefs=zeros(Int64,mCount,gCount)

    for m in unassignedMembers
        local memberPref = Array{Float16,1}(undef,gCount)
        for g in 1:gCount
            memberPref[g] = memberPrefForGroup(m,g)
        end
        gMemberPrefs[m,:] = sortperm(memberPref, rev=true);
    end
    return gMemberPrefs;
end
    

# -- helper. Generates each groups preference for unassigned members
function getGroupPrefForAllMembers(unassignedMembers)
    local groupPrefs=zeros(Float16,gCount,mCount)
    
    for g in 1:gCount
        for m in unassignedMembers
            groupPrefs[g,m] = groupPrefForMember(m,g)
        end
    end 
    return groupPrefs
end

#-- helper. calculates the groups avg votes for member
function groupPrefForMember(m,g,m2=0)
    global prefs, assignments, mCount, gCount, mPerG
    count = 0
    score = 0
    for gm in assignments[g]
        # if last member is reached break
        (gm==0) && break
        
        # m2 cannot vote as he is being replaced 
        (gm==m2) && continue 

        score += prefs[gm,m]
        count += 1
    end
    count==0 && (count=1)
    return Float16(score/count);
end
#-- end of group Pref for member

#-- helper. calculates the member preference for group
function memberPrefForGroup(m,g,m2=0)
    global prefs, assignments, mCount, gCount, mPerG
    count = 0
    score = 0
    for gm in assignments[g]
        # if last member is reached break
        (gm==0) && break
        
        # m2 does not need to be voted on as he is being replaced 
        (gm==m2) && continue 

        score += prefs[m,gm]
        count += 1
    end
    count==0 && (count=1)
    return Float16(score/count);
end
#-- end of memberprefforgroup

#-- Average of Pref 
function averagePrefOfGroup(g, withM=0, withoutM=0)
    global mCount, gCount, assignments, prefs
    

    local tAssignment = zeros(Int64,mPerG,1)
    
    tAssignment = filter( m -> m!=0 && m!=withoutM, assignments[g,:])
    (withM!=0) && push!(tAssignment, withM)
    #@show tAssignment
    count = 0
    score = 0.0
    
    for m in tAssignment
        for m2 in tAssignment
            m==m2 && continue
            (m==0 || m2==0) && continue
            count+=1
            score += prefs[m,m2]
            #println("$m $m2 $(prefs[m,m2])")
        end
    end
    count==0 && (count=1)
    #println("- $score $count")
    return Float16(score/count)
end
#-- end of Average of Pref

#-- Preference score of group
function averagePrefOfGroups()
    local count = 0
    local score = 0.0
    for g in 1:gCount
        for m in assignments[g,:]
            m==0 && break
            for m2 in assignments[g,:]
                m==m2 && continue
                m2==0 && break
                count+=1
                score += prefs[m,m2]
            end
        end
    end
    println("Count $count Score $score")
    return (Float16(score/count), Float16(score/thMaxScore))
end

#-- computes the theoritical max score
#-- May not be acheivable
#-- This is if every member got their first choice
function computeTheoriticalMaxScore()
    global mCount, gCount, assignments, prefs
    local tPrefs = zeros(Int64,mCount, gCount)
    for m=1:mCount
        tPrefs[m,:] = sort(prefs[m,:], rev=true)
    end
    
    return reduce(+,tPrefs[:,1:gCount])
end

#-- Read the data from File
function loadPreferenceData()
    global config, prefs, mCount, assignments, thMaxScore

    dataFile = config["dataFile"]
    data = readdlm(dataFile, ',', Int64)
    
    global mPrefs, mCount
    println("member count is $mCount")
    
    prefs = zeros(Int64,mCount,mCount)
    for mmv in eachrow(data)
        prefs[mmv[1],mmv[2]] = (mmv[1]!=mmv[2] ? mmv[3] : 0)
    end
    #thMaxScore = computeTheoriticalMaxScore()
    # assignments = zeros(Int64, gCount, mPerG)
    
    #happiness = zeros(Int64,mCount, 2)
    #happiness[:,1] .= -2    # first col is member happiness. -2 for not being assigned to a cabin yet
    #mPrefs = hcat(mPrefs,cabinAssignment,1:mCount)
end

#-- Loads the config
function loadConfig(configFile)
    global mCount, gCount, mPerG, argDict, setFileName
    
    #global colCabin, colKNum, colCVotes, colKVote

    global config = YAML.load_file(configFile)

    mCount          = config["members"]
    gCount          = config["groups"]

    mPerG       = config["mPerG"] 

    if (mPerG < mCount/gCount) 
        mPerG = convert(Int64,ceil(mCount/gCount))
        println("Not enough groups. Increased groups to $mPerG")
    end
    
    #cabins *= 3
    # some constants
    #colCabin    = mCount + 1   # col for cabin assignment 
    #colKVote    = mCount + 2   # col for kids vote for this cabin
    #colCVotes   = mCount + 3  # col for cabins vote for this kid
    #colKNum     = mCount + 4    # col for the number of this kid
end




#-- The runner 
if abspath(PROGRAM_FILE) == @__FILE__
    # just call main
    main()
else 
    # do this from repl 
    # include("datagen.jl")
    # setup some defaults for REPL testing
    
    # Stable Marriage
    #global configFile = "config/ma-config-m12-g6-SM-1.yaml"
    
    # Stable 
    global configFile = "config/ma-config-m16-g4-GEN-1.yaml"
    println("Matching v0.03. Config File $configFile")
    loadConfig(configFile)
    loadPreferenceData()
    "Loaded."
end

#end # end of module
