# module Kc
using DelimitedFiles
using YAML
using Logging

#kCount=200
#cabins=20

# Setup Logging
#logIo = open("KidsCabin.log", "w+")
#logger = SimpleLogger(logIo)
#global_logger(logger)
# LogLevel(Logging.Debug)   # Debug, Info, Warn, Error

# Keep the argument dictionary
#argDict = Dict()




# some constants
#colCabin = kCount + 1   # col for cabin assignment 
#colKVote = kCount + 2   # col for kids vote for this cabin
#colCVotes = kCount + 3  # col for cabins vote for this kid
#colKNum = kCount + 4    # col for the number of this kid

#kPref = zeros(Int64,kCount,kCount)

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
    println("TestDataGen v0.01. Config File $configFile")
    loadConfig(configFile)
    
    # read the kids preference file
    readData(dFileName)             # read the data
    
    # Initial Round of assignments
    initialRound()
    println("\nHappiness Coefficient after initial Round: $(happinessCoefficient())")

    
    local kPrevChangeCount = 0
    local noChangeCount = 0
    local totalVotes = reduce(+,kPref[:,1:kCount])
    for i=1:500
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
    

    writeAssignment(config["assingments"])      # prints the assignments to a file
    printSummaryOfAssignments()
end

function printSummaryOfAssignments()
    for c=1:cabins                                                                                                                                                  
        print("$c")                                                                                                                                                  
        for k in getKidsinCabin(c)                                                                                                                                   
           print(",$k")                                                                                                                                              
        end                                                                                                                                                          
        println("")                                                                                                                                                  
     end

     println("\nHappiness Coefficient: $(happinessCoefficient())")
end

happinessCoefficient() = round( (reduce(+,kPref[:,colKVote])/reduce(+,kPref[:,1:kCount]) ), digits=4)

# Initial Round. No kick outs in this Round
function initialRound()
    global kPref, cabins, kCount, kPerCabin

    # This is initial round. Lets randomize
    # korder = sortperm(kPref[:,colKVote])

    korder = sortperm(rand(kCount))
    
    c = 1
    assignedToC = 0         # Number of kids assigned in this round
    push!(korder,0)         # Round marker
    takeNextCabin = true    # The next kid will take the best cabin availble
    kInCabin = 0            # How many kids in the current cabin we are filling  

    kRejectCount = zeros(Int64,kCount)  # Track how many times a kid was rejected from a cabin

    while (true) 
        
        #=
        if (kInCabin >=kPerCabin)

            # Get cabin with least kids
           c, kInCabin = getNextCabin()
            
            if (kInCabin>=kPerCabin) 
                # done with cabins this round
                break;
            end
            assignedToC = 0
            takeNextCabin=true
        end
        =#

        # take first kid
        k = popfirst!(korder)
        #println("K $k C $c")
        if (k==0) # we have come a full circle
            #println("Full circle")
            
            # Done with everybody?
            #(size(korder,1)==0) && break;

            if (assignedToC==0)
                c, kInCabin = getNextCabin()
                
                if (kInCabin>=kPerCabin || size(korder,1)==0) 
                    break;
                end
                takeNextCabin=true
                kRejectCount = zeros(Int64,kCount)
            end
            assignedToC = 0
            
            push!(korder,k)
            continue
        end

        voteForCabin = kAdjustedScoreForCabin(k,c)
        # kids knows someone in this cabin
        if (voteForCabin>0 || takeNextCabin==true)
            #println("--  $k -> $c  : $voteForCabin")
            if (kInCabin<kPerCabin) # there is space
                assignKtoCabin(k,c);
                assignedToC += 1
                kInCabin += 1
            else # there is no space in this cabin
                # Would the cabin mates like to vote someone out?
                voteByCabin = kScoreByCabin(k,c)
                lowestVotedKids = getKWithLowestVotes(c)
                #println("Kid $lowK has score $lowV. New kid $k has score $voteByCabin")
                if (lowestVotedKids[1][1]<voteByCabin) 
                    # kick kid out
                    
                    #for kv in lowestVotedKids
                    #    assignKtoCabin(kv[2],0)
                    #end
                    kVotedOut = lowestVotedKids[rand(1:end)][2]
                    if (kRejectCount[kVotedOut]<3)
                        println("Must kick out K $kVotedOut - $(kRejectCount[kVotedOut])th time out of C $c to be replaced by $k with $voteByCabin votes")
                        #println(lowestVotedKids)
                        assignKtoCabin(kVotedOut,0)
                        kRejectCount[kVotedOut] += 1

                        push!(korder,kVotedOut)
                    
                        assignKtoCabin(k,c)

                        assignedToC += 1
                    end
                end    
            end    
            takeNextCabin = false
        else 
            push!(korder,k)
        end
    end
    
    return 1

end

# fetches the next most empty cabin
function getNextCabin()
    global cabins
    cabinsKids = hcat(1:cabins,map(c-> kCountInCabin(c), 1:cabins))
    cabinsKids = cabinsKids[sortperm(cabinsKids[:,2]),:]
    return (cabinsKids[1,1],cabinsKids[1,2])
end

function unassignUnhappyKids() 
    # for each kid
    global kPref,cabins,kCount, kPerCabin
        
    local kChangeCount = 0
    korder = sortperm(kPref[:,colKVote])
    for k in korder
        for c in 1:cabins
            lowestVotedKids = getKWithLowestVotes(c)
            if size(lowestVotedKids,1)<=3
                for kv in lowestVotedKids
                    assignKtoCabin(kv[2],0)
                end
            end
        end
    end
end


function assignmentRound() 
    # for each kid
    global kPref,cabins,kCount, kPerCabin
    
    local kChangeCount = 0
    korder = sortperm(kPref[:,colKVote])
    

    for k in korder
        # kPref[k,kCount+2] = kScoreForCabin(k)
        # Score for each cabin by the kid
        #local cabinScores = sort( map(c->([c,kScoreForCabin(k,c),kCountInCabin(c)]),1:cabins) ,by= x-> x[2], rev=true)
        #csc = map(c->([c,kScoreForCabin(k,c),kCountInCabin(c)]),1:cabins)
        csc = hcat(1:cabins, map(c-> (kAdjustedScoreForCabin(k,c)), 1:cabins), map(c-> (kCountInCabin(c)), 1:cabins) )
        #println(csc)
        cabinScores = csc[sortperm(100 .* csc[:,2] .- csc[:,3], rev=true),:]
        #println(cabinScores)
        #tarr[sortperm(100 .* tarr[:,1] .+ tarr[:,2]),:]
        #println("Start to examine kid $k  ",cabinScores)
        local voteForCurrentCabin = kCurrentHappiness(k)
            
        for cs in eachrow(cabinScores)
            local c = cs[1]
            local voteForNewCabin = cs[2]
            local kidsInCabin = cs[3]
            #println(cs);
            #println("Examining $c new vote $voteForNewCabin. Old vote was $voteForCurrentCabin")
            if voteForNewCabin <= voteForCurrentCabin 
                # all other cabins after this point will be rated lower
                #println("$k is happy in $c")
                #if (voteForNewCabin != voteForCurrentCabin) || (rand()<0.20)
                    break
                #end
            end
                
        
            # kid will be happier in this cabin
            # check with cabin
            if (kidsInCabin < kPerCabin)
                #println("Cabin $c has space for $k. Assign")
                # cabin is not at capacity. Assign the kid
                assignKtoCabin(k,c);
                kChangeCount+=1
                break;
            else
                # can we kick someone out? Get the kid with the lowest cabin votes in this cabin
                #println("Cabin $c has NO space for $k. Can we kick someone out?")
                voteByCabin = kScoreByCabin(k,c)
                lowestVotedKids = getKWithLowestVotes(c)
                #println("Kid $lowK has score $lowV. New kid $k has score $voteByCabin")
                if (lowestVotedKids[1][1]<voteByCabin) 
                    # kick kid out
                    #println("Must kick $lowK out to replaced by $k")
                    for kv in lowestVotedKids
                        assignKtoCabin(kv[2],0)
                    end
                    #assignKtoCabin(lowestVotedKids[rand(1:end)][2],0)
                    assignKtoCabin(k,c)
                    kChangeCount+=1
                    break;
                end
            end
        end
    end
    
    return kChangeCount
end


function loadConfig(configFile)
    global kCount, cabins, kPerCabin, dFileName, argDict, chainLength,setFileName
    global colCabin, colKNum, colCVotes, colKVote
    global config = YAML.load_file(configFile)

    kCount          = config["kCount"]
    cabins          = config["cabins"]
    chainLength     = config["chainLength"]
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
kCurrentHappiness(k) = kPref[k,kCount+2]
kCountInCabin(c) = size(kPref[(kPref[:,colCabin] .== c),colKNum])[1]

function loadSample() 
    global kPref,cabins,kCount, kPerCabin
    setConfig(500,50)
    readData("data-k500-c20-B.csv")
end



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

# A kids score in cabin as viewed by his cabin mates. 0 is unassigned
# since the kid cannot vote for himself, we dont need to take him out
function kScoreByCabin(k, cabin= kPref[k,kCount+1]) 
    global kPref, kCount
    
    if (cabin==0) 
        return 0 
    end
    # get cabin assignment for kid
    reduce(+,kPref[(kPref[:,kCount+1] .== cabin),k])
end

function kScoreForCabin(k, cabin= kPref[k,colCabin])
    global kPref, kCount

    if (cabin==0) 
        return -2  # preference -2 if no assigned cabin
    end
    
    reduce(+,kPref[k, transpose(kPref[(kPref[:,kCount+1] .== cabin),end])])
end

function kAdjustedScoreForCabin(k, c= kPref[k,colCabin])
    global kPref, kCount, kPerCabin

    if (c==0) 
        return -2  # preference -2 if no assigned cabin
    end
    
    kvotes = kPref[(kPref[:,colCabin] .== c),[colCVotes,colKNum]]
    if (size(kvotes,1)<kPerCabin)
        return reduce(+,kPref[k, transpose(kPref[(kPref[:,kCount+1] .== c),end])])
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

# Load data
function readData1() 
    data = readdlm("assigned-data-gen.csv", ',', Int64)
    dima = size(data)[1]

    global kPref, kCount
    kPref = zeros(Int64,kCount,kCount)
    for i=1:size(data)[1]
        for j=1:size(data)[2]
            kPref[data[i,j],data[i,1 + j%dima]] = 2
            kPref[data[i,j],data[i,1 + (j-2+5)%dima]] = 2
        end
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
    push!(ARGS,"config-k50-c5-C1.yaml")
    configFile = ARGS[1]
    println("TestDataGen v0.01. Config File $configFile")
    loadConfig(configFile)
    readData(dFileName)
    "Loaded."
end

#end # end of module