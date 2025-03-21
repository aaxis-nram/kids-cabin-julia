# module Kc
using DelimitedFiles
using YAML
using Logging

# ENV["JULIA_DEBUG"] = Main

# main runner
function main() 
    global kCount, cabins, kPerCabin, kPref

    
    # Config file provided?
    if (size(ARGS,1)==0)
        # print usage
        println("Usage: julia TestDataGen.jl configFile.yaml")
        exit()
    end

    # Load Config
    configFile = ARGS[1]
    loadConfig(configFile)
    
    # Setup logging
    @info("TestDataGen v0.01. Config File $configFile")
    @info("Running config " * config["name"])
    
    # read the kids preference file
    @debug("Loading preference data from dFileName")
    readData(dFileName)             # read the data
    
    # Initial Round of assignments
    @info("Performing Initial Assignment")
    initialRound()
    @info("Happiness Coefficient after initial Round: $(happinessCoefficient())")
    printSummaryOfAssignments()
    
    
    local kPrevChangeCount = 0
    local noChangeCount = 0
    local totalVotes = reduce(+,kPref[:,1:kCount])
    for i=1:1
        kChangeCount = assignmentRound()
        
        println("$i,$kChangeCount,$(happinessCoefficient())");
        if (kChangeCount==kPrevChangeCount)
            noChangeCount += 1
            if ((kChangeCount==0 && noChangeCount>=3) || noChangeCount>=50)
                println("No changes for $noChangeCount iterations after $i iterations.")
                break
            end
        else
            noChangeCount = 0
            kPrevChangeCount = kChangeCount
        end
        #unassignUnhappyKids()
        
    end
    

    @debug("Writing assignment to " * config["assignments"])
    writeAssignment(config["assignments"])      # prints the assignments to a file
    printSummaryOfAssignments()
end

function printSummaryOfAssignments()
    local cabinMates = []
    for c=1:cabins                                                                                                                                                  
        push!(cabinMates,getKidsinCabin(c))
    end
    cabinMates = cabinMates[sortperm(cabinMates, by=x->x[1])]
    for cm in cabinMates
        for c in cm
            print("|" * lpad(c,3," "))
        end
        println("|")
    end
    println("\nHappiness Coefficient: $(happinessCoefficient())")
end

# happinessCoefficient Definition. 
function happinessCoefficient()
    global kCount, kPref, kPerCabin
    local max     = 0
    local current = reduce(+,kPref[:,colKVote])
    for k=1:kCount
        max += reduce(+,sort(kPref[k,1:kCount],rev=true)[1:kPerCabin-1])
    end # of next
    round( current/max , digits=4)
end

# Initial Round. No kick outs in this Round
function initialRound()
    global kPref, cabins, kCount, kPerCabin

    resetAssignments()

    # This is initial round. Lets randomize
    korder = sortperm(rand(kCount))
    
    c = 1
    assignedToC = 0         # Number of kids assigned in this round
    push!(korder,0)         # Round marker
    takeNextCabin = true    # The next kid will take the best cabin availble
    kInCabin = 0            # How many kids in the current cabin we are filling  

    kChangeCount = 0
    round = 0
    pinned = Array{Bool,1}(undef, kCount)
    pinned[:] .= false
    while (true) 
        # take first kid
        round += 1
        #if (round>100) 
        #    exit()
        #end
        k = popfirst!(korder)
        
        @debug("--------------- K $k C $c")
        @debug("$round: Kids in $(getKidsinCabin(c))")
        if (k==0) # we have come a full circle
            @debug "Reached circle marker. Assigned $kChangeCount"
            
            # Done with everybody?
            if (size(korder,1)==0)
                @debug "All kids assigned"
                break
            end

            # how many kids were assigned since we kit the circle marker
            if (assignedToC==0)
                c, kInCabin = getNextCabin()
                
                # That function returns the least populated cabin. 
                # if that one is full than all are full
                if (kInCabin>=kPerCabin) 
                    @debug "No more space"
                    break
                end

                # We just opened/reopned a cabin. The next kid must take that cabin. No choice.
                takeNextCabin=true
            end

            # so we reset the assignment count since circle marker
            assignedToC = 0
            
            # push the circle marker 
            push!(korder,k)
            continue
        end

        # get the scores for the cabins. Adjusted scores only account for
        # the first kCount-1 kids in the cabin ordered by kids votes for one
        # another. Assumption is kCount kid will be voted out of the cabin 
        # and shouldn't count
        
        if (kInCabin<kPerCabin) 
            voteForCabin = takeNextCabin ? 1 : kScoreForCabin(k,c)
            # Does the kid know someone in this cabin? 
            if (voteForCabin>0)
                # there is space
                assignKtoCabin(k,c);
                assignedToC += 1
                kInCabin += 1
                kChangeCount += 1

                if (takeNextCabin) 
                    # pin this user
                    pinned[k]=true
                    @debug("--- Pinned $k")
                    takeNextCabin = false
                end
                continue
            end
            
        else
            # there is no space in this cabin
            # Would the cabin mates like to vote someone out?
            local myPrefs = []
            for kVo in getKidsinCabin(c)
                pinned[kVo] && continue
                voteForCabin = kScoreForCabinWithoutKVo(k,c,kVo)
                @debug("Can we kickout $kVo from $c: Preference without is $voteForCabin")
                if (voteForCabin > 0) 
                    push!(myPrefs,c,kVo,voteForCabin)
                end 
            end
            myPrefs = reshape(myPrefs,3,:)'
            myPrefs = myPrefs[sortperm(myPrefs[:,3], rev=true),:]
            foundSlot = false
            @debug(myPrefs);
            for mp in eachrow(myPrefs) 
                @debug("Evaluating $mp")
                kVotedOut = mp[2]
                
                #(kRejectCount[kVotedOut]>=3) && continue

                voteByCabinForN = kScoreByCabinWithoutKVo(k,c,kVotedOut)
                VotesForkVotedOut = kPref[kVotedOut,colCVotes]
                VotesForkVotedOut1 = kScoreByCabinWithoutKVo(kVotedOut,c,kVotedOut)
                @debug(" For N $voteByCabinForN for kVo $VotesForkVotedOut:$VotesForkVotedOut1")

                if (voteByCabinForN > VotesForkVotedOut)
                    # Yes, the new kid has more votes from his cabin mates
                    
                    @debug "-- Voted out"
                    
                    # unassign 
                    assignKtoCabin(kVotedOut,0)
                    # kRejectCount[kVotedOut] += 1
                    push!(korder,kVotedOut)
                
                    # assign new kid
                    assignKtoCabin(k,c)
                    kChangeCount += 1
                    assignedToC += 1
                    takeNextCabin = false
                    foundSlot = true
                    break
                end
            end
            foundSlot && continue
        end    
                    
        push!(korder,k)
    end
    
    return kChangeCount

end

function resetAssignments()
    kPref[:,colCabin]  .= 0
    kPref[:,colCVotes] .= 0
    kPref[:,colKVote]  .= -2
end


# Initial Round. No kick outs in this Round
function assignmentRound()
    global kPref, cabins, kCount, kPerCabin

    # order by most unhappy
    korder = sortperm(kPref[:,colKVote])
    
    assignedToC = 0         # Number of kids assigned in this round
    push!(korder,0)         # Round marker
    takeNextCabin = true    # The next kid will take the best cabin availble

    kRejectCount = zeros(Int64,kCount)  # Track how many times a kid was rejected from a cabin
    kChangeCount = 0
    round = 0

    while (true) 
        
        round += 1
        #if (round>100) 
        #    exit()
        #end
        k = popfirst!(korder)
        
        @debug("K $k")
        
        if (k==0) # we have come a full circle
            @debug "Reached circle marker. Assigned $kChangeCount $assigned"
            
            # Done with everybody?
            if (size(korder,1)==0)
                @debug "All kids assigned"
                break
            end

            if (assignedToC==0)
                break
            end
            # so we reset the assignment count since circle marker
            assignedToC = 0
            
            # push the circle marker 
            push!(korder,k)
            continue
        end

        for c=1:cabins
            local myPrefs = []
            (c==kPref[k,colCabin]) && continue
            local voteForCurrentCabin = kCurrentHappiness(k)
                
            if (kCountInCabin(c)<kPerCabin) 
                voteForCabin = kScoreForCabin(k,c)
                
                # Does the kid know someone in this cabin? 
                @debug("Does $k like $c ($voteForCabin) or current cabin $(kPref[k,colCabin]) ($voteForCurrentCabin)")
                if (voteForCabin > voteForCurrentCabin)
                    # there is space
                    push!(myPrefs,c,0,voteForCabin)
                end
            else
                for kVo in getKidsinCabin(c)
                    
                    voteForCabin = kScoreForCabinWithoutKVo(k,c,kVo)
                    @debug("Does $k like $c without $kVo ($voteForCabin) or current cabin $(kPref[k,colCabin]) ($voteForCurrentCabin)")
                    if (voteForCabin > voteForCurrentCabin) 
                        push!(myPrefs,c,kVo,voteForCabin)
                    end 
                end
            end
            myPrefs = reshape(myPrefs,3,:)'
            myPrefs = myPrefs[sortperm(myPrefs[:,3], rev=true),:]
            foundSlot = false
            @debug("$k preference by cabin")
            @debug(myPrefs);
        
            for mp in eachrow(myPrefs) 
                @debug("Evaluating $mp")
                kVotedOut = mp[2]
                
                #(kRejectCount[kVotedOut]>=3) && continue

                voteByCabinForN = kScoreByCabinWithoutKVo(k,c,kVotedOut)
                VotesForkVotedOut = kVotedOut==0 ? -2 : kScoreByCabinWithoutKVo(kVotedOut,c,kVotedOut)
                @debug(" For N $voteByCabinForN for kVo $VotesForkVotedOut")

                if (voteByCabinForN > VotesForkVotedOut)
                    # Yes, the new kid has more votes from his cabin mates
                    
                    @debug "$kVotedOut was Voted out of $c (V $VotesForkVotedOut) by $k (V $voteByCabinForN): Rej Count $(kRejectCount[kVotedOut])"
                    
                    # unassign 
                    if (kVotedOut!=0)
                        assignKtoCabin(kVotedOut,0)
                        kRejectCount[kVotedOut] += 1
                        push!(korder,kVotedOut)
                    end
                    # assign new kid
                    assignKtoCabin(k,c)
                    kChangeCount += 1
                    assignedToC += 1
                    takeNextCabin = false
                    foundSlot = true
                    break
                end
            end
            foundSlot && continue
        end    
                    
        push!(korder,k)
    end
    
    return kChangeCount

end

# fetches the next most empty cabin
function getNextCabin()
    global cabins
    cabinsKids = hcat(1:cabins,map(c-> kCountInCabin(c), 1:cabins))
    cabinsKids = cabinsKids[sortperm(cabinsKids[:,2]),:]
    return (cabinsKids[1,1],cabinsKids[1,2])
end

function getPreferencesForCabins(k) 
    local voteForCurrentCabin = kCurrentHappiness(k)
    local myPrefs = []
    for c=1:cabins
        
        # this is the current cabin cabin
        (c==kPref[k,colCabin]) && continue
            
        # how many people in this cabin?
        if (kCountInCabin(c)<kPerCabin) 
            # There is a spot. No one needs to leave
            voteForCabin = kScoreForCabin(k,c)
            
            # Does the kid know someone in this cabin? 
            @debug("Does $k like $c ($voteForCabin) or current cabin $(kPref[k,colCabin]) ($voteForCurrentCabin)")
            if (voteForCabin > voteForCurrentCabin)
                # there is space
                push!(myPrefs,c,0,voteForCabin)
            end
        else
            # Cabin is full. Let's see who should leave
            for kVo in getKidsinCabin(c)
                voteForCabin = kScoreForCabinWithoutKVo(k,c,kVo)
                @debug("Does $k like $c without $kVo ($voteForCabin) or current cabin $(kPref[k,colCabin]) ($voteForCurrentCabin)")
                if (voteForCabin > voteForCurrentCabin) 
                    push!(myPrefs,c,kVo,voteForCabin)
                end 
            end
        end
    end
    myPrefs = reshape(myPrefs,3,:)'
    myPrefs = myPrefs[sortperm(myPrefs[:,3], rev=true),:]

    # consolidate the request to the cabin mates.
    myCPref = []
    prevC = undef
    prevV = undef
    kVos = []
    for kv in eachrow(myPrefs) 
        if prevC!=undef && (kv[1]!=prevC || kv[3]!=prevV) 
            push!(myCPref,prevC,kVos,prevV)
            prevC = kv[1]
            prevV = kv[3]
            kVos = [kv[2]]
        else   
            push!(kVos,kv[2])
        end
    end
    if (size(kVos,1) > 0)
        push!(myCPref,prevC,kVos,prevV)
    end
    myCPref = reshape(myCPref,3,:)'
    @debug("$k preference by cabin")
    
    return myCPref
end

function loadConfig(configFile)
    global kCount, cabins, kPerCabin, dFileName, argDict,setFileName
    global colCabin, colKNum, colCVotes, colKVote
    global config = YAML.load_file(configFile)

    kCount          = config["kCount"]
    cabins          = config["cabins"]
    dFileName       = config["dataFile"]

    kPerCabin       = config["kPerCabin"] 
    if (kPerCabin < kCount/cabins) 
        kPerCabin = convert(Int64,ceil(kCount/cabins))
        println("Not enough cabin. Increased cabins to kPerCabin")
    end
    #cabins *= 3
    # some constants
    colCabin    = kCount + 1   # col for cabin assignment 
    colKVote    = kCount + 2   # col for kids vote for this cabin
    colCVotes   = kCount + 3  # col for cabins vote for this kid
    colKNum     = kCount + 4    # col for the number of this kid
end

function writeAssignment(outFile)
    println("Writing to file $outFile")
    global kPref

    writedlm( outFile, kPref[:,[colKNum, colCabin,colKVote,colCVotes]], ',')
end

# helper functions
kCurrentHappiness(k) = kPref[k,colKVote]
kCountInCabin(c) = size(kPref[(kPref[:,colCabin] .== c),colKNum])[1]


# identifies and returns the kids with the lowest vote count in the cabin
function getKWithLowestVotes(cabin) 
    lowestVotedKids = []
    lowestVotes = typemax(Int64)
    
    for kv in eachrow(kPref[(kPref[:,colCabin] .== cabin),[colCVotes,colKNum]])
        if (kv[1] < lowestVotes)
            lowestVotes = kv[1]
            lowestVotedKids = [(kv[1],kv[2])]
        elseif (kv[1] == lowestVotes) 
            # another kid with low votes. collect them all
            push!(lowestVotedKids,(kv[1],kv[2]))
        end
    end

    # there may be better way to pick the kid to kickout. But for now random it is ...
    return lowestVotedKids;
    #return (lowestVotedKids[rand(1:end)])
end

function kScoreByCabinWithoutKVo(k,c,kVo) 
    global kPref, kCount
    
    if (c==0) 
        return 0 
    end
    # get cabin assignment for kid
    return reduce(+,kPref[(kPref[:,colCabin] .== c .&& kPref[:,colKNum] .!= kVo),k])
        
end
        
function kScoreForCabinWithoutKVo(k, c,kVo)
    global kPref, kCount

    if (c==0) 
        return -2  # preference -2 if no assigned cabin
    end
    
    reduce(+,kPref[k, transpose(kPref[(kPref[:,colCabin] .== c .&& kPref[:,colKNum] .!= kVo),end])])
end

# A kids score in cabin as viewed by his cabin mates. 0 is unassigned
# since the kid cannot vote for himself, we dont need to take him out
function kScoreByCabin(k, cabin= kPref[k,colCabin]) 
    global kPref, kCount
    
    if (cabin==0) 
        return 0 
    end
    # get cabin assignment for kid
    reduce(+,kPref[(kPref[:,colCabin] .== cabin),k])
end

# A kids score in cabin as viewed by his cabin mates. 0 is unassigned
# since the kid cannot vote for himself, we dont need to take him out
function kAdjustedScoreByCabin(k, c, kVotedOut ) 
    global kPref, kCount, colCabin, colKNum
    
    if (c==0) 
        return 0 
    end
    # get cabin assignment for kid
    reduce(+,kPref[(kPref[:,colCabin] .== c .&& kPref[:,colKNum] .!= kVotedOut),k])
end


function kScoreForCabin(k, cabin= kPref[k,colCabin])
    global kPref, kCount

    if (cabin==0) 
        return -2  # preference -2 if no assigned cabin
    end
    
    reduce(+,kPref[k, transpose(kPref[(kPref[:,colCabin] .== cabin),end])])
end

function kAdjustedScoreForCabin(k, c= kPref[k,colCabin])
    global kPref, kCount, kPerCabin

    if (c==0) 
        return -2  # preference -2 if no assigned cabin
    end
    
    kvotes = kPref[(kPref[:,colCabin] .== c),[colCVotes,colKNum]]
    if (size(kvotes,1)<kPerCabin)
        return reduce(+,kPref[k, transpose(kPref[(kPref[:,colCabin] .== c),end])])
    else
        kvotes = kvotes[sortperm(kvotes[:,1]),:]
        return reduce(+,kPref[k, transpose(kvotes[2:end,2])])
    end
end



function assignKtoCabin(k,cabin) 
    global kPref, colCabin,colKVote, colCVotes
    
    #println(k,":",cabin, col)
    # first assign the kid
    kPref[k,colCabin] = cabin
    #println(kPref[k,:])

    # update votes for all kids in the cabin
    for kv in eachrow(kPref[(kPref[:,colCabin] .== cabin),[colKNum]])
        #println(kv)
        kPref[kv[1],colKVote] = kScoreForCabin(kv[1])
    end

    # update cabins votes for all the kid
    for kv in eachrow(kPref[(kPref[:,colCabin] .== cabin),[colKNum]])
        kPref[kv[1], colCVotes] = kScoreByCabin(kv[1])
    end
    # update votes for rest of kids in cabin

    
end

getKidsinCabin(cabin) = kPref[(kPref[:,colCabin] .== cabin),[colKNum]]


function readData(dataFile)
    data = readdlm(dataFile, ',', Int64)
    global kPref, kCount
    #println("kCount is $kCount")
    kPref = zeros(Int64,kCount,kCount)
    for kkv in eachrow(data)
        kPref[kkv[1],kkv[2]] = kkv[3]
    end

    cabinAssignment = zeros(Int64,kCount,3)
    cabinAssignment[:,2] .= -2    # second col is kid happiness. -2 for not being assigned to a cabin yet
    kPref = hcat(kPref,cabinAssignment,1:kCount)
end



# The runner 
if abspath(PROGRAM_FILE) == @__FILE__
    # just call main
    main()
else 
    # do this from repl 
    # include("datagen.jl")
    # setup some defaults for REPL testing
    
    global configFile = "config/config-k12-c6-SM1.yaml"
    println("KidsCabin v0.02. Config File $configFile")
    loadConfig(configFile)
    readData(dFileName)
    "Loaded."
end

#end # end of module