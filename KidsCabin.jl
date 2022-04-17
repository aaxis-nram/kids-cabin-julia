# module Kc
using DelimitedFiles
using YAML
using Logging

kCount=200
cabins=20

# Setup Logging
#logIo = open("KidsCabin.log", "w+")
#logger = SimpleLogger(logIo)
#global_logger(logger)
LogLevel(Logging.Debug)   # Debug, Info, Warn, Error

# Keep the argument dictionary
argDict = Dict()


kPerCabin = convert(Int64,ceil(kCount/cabins))

# some constants
colCabin = kCount + 1   # col for cabin assignment 
colKVote = kCount + 2   # col for kids vote for this cabin
colCVotes = kCount + 3  # col for cabins vote for this kid
colKNum = kCount + 4    # col for the number of this kid

kPref = zeros(Int64,kCount,kCount)

# main runner
function main() 
    global kCount, cabins, kPerCabin
    setConfig(inarg("kCount",200), inarg("cabins",20))
    
    readData(inarg("datafile","data-200-20-10.csv"))              # read the data
    
    local kPrevChangeCount = 0
    local noChangeCount = 0
    for i=1:500
        kChangeCount = assignmentRound()
        println("$i,$kChangeCount");
        if (kChangeCount==kPrevChangeCount)
            noChangeCount += 1
            if ((kChangeCount==0 && noChangeCount>=3) || noChangeCount>=10)
                println("No changes for $noChangeCount iterations after $i iterations.")
                break
            end
        else
            noChangeCount = 0
            kPrevChangeCount = kChangeCount
        end
        
    end

    writeAssignment(inarg("outfile","assignments-1.csv"))      # prints the assignments to a file
end
function setConfig(pkCount, pCabins) 
    global kCount, cabins, kPerCabin, colCabin, colKNum, colCVotes, colKVote

    kCount=pkCount
    cabins=pCabins
    
    kPerCabin = convert(Int64,ceil(kCount/cabins))

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
kCountInCabin(k) = size(kPref[(kPref[:,kCount+1] .== k),colKNum])[1]

function loadSample() 
    global kPref,cabins,kCount, kPerCabin
    setConfig(500,50)
    readData("data-k500-c20-B.csv")
end

# initial assignment
function assignmentRound() 
    # for each kid
    global kPref,cabins,kCount, kPerCabin
    
    local kChangeCount = 0
    korder = sortperm(kPref[:,colKVote])
    #korder = sortperm(rand(kCount))
    for k in korder
        # kPref[k,kCount+2] = kScoreForCabin(k)
        # Score for each cabin by the kid
        #local cabinScores = sort( map(c->([c,kScoreForCabin(k,c),kCountInCabin(c)]),1:cabins) ,by= x-> x[2], rev=true)
        #csc = map(c->([c,kScoreForCabin(k,c),kCountInCabin(c)]),1:cabins)
        csc = hcat(1:cabins, map(c-> (kScoreForCabin(k,c)), 1:cabins), map(c-> (kCountInCabin(k)), 1:cabins) )
        #println(csc)
        cabinScores = csc[sortperm(100 .* csc[:,2] .- csc[:,3]),:]
        #println(cabinScores)
        #tarr[sortperm(100 .* tarr[:,1] .+ tarr[:,2]),:]
        #println("Start to examine kid $k  ",cabinScores)
        local voteForCurrentCabin = kCurrentHappiness(k);

        for cs in eachrow(cabinScores)
            local c = cs[1]
            local voteForNewCabin = cs[2]
            local kidsInCabin = cs[3]
            #println(cs);
            #println("Examining $c new vote $voteForNewCabin. Old vote was $voteForCurrentCabin")
            if voteForNewCabin < voteForCurrentCabin 
                # all other cabins after this point will be rated lower
                #println("$k is happy in $c")
                break
            end
                
        
            # kid will be happier in this cabin
            # check with cabin
            if (kCountInCabin(c) < kPerCabin)
                #println("Cabin $c has space for $k. Assign")
                # cabin is not at capacity. Assign the kid
                assignKtoCabin(k,c);
                kChangeCount+=1
                break;
            else
                # can we kick someone out? Get the kid with the lowest cabin votes in this cabin
                #println("Cabin $c has NO space for $k. Can we kick someone out?")
                voteByCabin = kScoreByCabin(k,c)
                (lowV,lowK) = getKWithLowestVotes(c)
                #println("Kid $lowK has score $lowV. New kid $k has score $voteByCabin")
                if (lowV<voteByCabin) 
                    # kick kid out
                    #println("Must kick $lowK out to replaced by $k")
                    assignKtoCabin(lowK,0)
                    assignKtoCabin(k,c)
                    kChangeCount+=1
                    break;
                end
            end
        end

    end
    
    return kChangeCount
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
    return (lowestVotedKids[rand(1:end)])
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

function kScoreForCabin(k, cabin= kPref[k,kCount+1])
    global kPref, kCount

    if (cabin==0) 
        return -2  # preference -2 if no assigned cabin
    end
    
    reduce(+,kPref[k, transpose(kPref[(kPref[:,kCount+1] .== cabin),end])])
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

function inarg(key, def)
    p = get(argDict,key,nothing)

    if (p===nothing) 
        return def
    elseif (typeof(def)!=typeof("String"))
        return parse(typeof(def),p)
    else 
        return p
    end
end

function testData()
    readData()
    assignKtoCabin(1,1)
    assignKtoCabin(3,1)
    assignKtoCabin(4,1)
    assignKtoCabin(5,1)
    
    println(kScoreByCabin(1))
end
# The usual addon for batch running and args
function inarg(key, def)
    p = get(argDict,key,nothing)

    if (p===nothing) 
        return def
    elseif (typeof(def)!=typeof("String"))
        return parse(typeof(def),p)
    else 
        return p
    end
end

# entry point 
if abspath(PROGRAM_FILE) == @__FILE__
    # load config 
    println("Kids-Cabins Assignment Problem Solver v0.1")
    global argDict = Dict()
    map(arg-> begin
                if !((m=match(r"(\S+)=(\S+)",arg)) === nothing)
                    argDict[m[1]] = m[2]
                else
                    argDict[arg] = true
                end
            end,ARGS )
    main()
else 
    # setup some defaults for REPL testing
   
end

#end # end of module