"""
    RankLeafPruningWindow(;rank, rank_window, age_window_start, age_window_end)

Function to remove leaf biomass and area when the phytomer 1/ has an harvested bunch or 2/ when the leaf reaches a given rank (usefull for male phytomers) or
3/ the leaves are manually pruned under a certain rank during a time period. 

# Arguments

- `rank`: leaf rank after which the leaf is cutted for management purpose
- `rank_window`: rank of the leaves to be pruned during a given time window (usually for manual pruning below `rank`)
- `start_date::Dates.Date`: start of the time window
- `end_date::Dates.Date`: end of the time window
- `duration::Dates.Period`: duration of the time window (if given instead of `end_date`, the end date is computed as `start_date + duration`)

# Inputs

- `state`: phytomer state
- `rank`: rank of the leaf
- `biomass`: biomass of the leaf
- `leaf_area`: leaf area of the leaf
- `state_phytomers`: state of the phytomers

# Outputs 

- `litter_leaf`: leaf biomass removed from the plant and going to the litter
- `pruning_decision`: decision taken for the leaf pruning
- `is_pruned`: boolean indicating if the leaf is pruned or not

"""
struct RankLeafPruningWindow{T,D} <: XPalmModel.Models.AbstractLeaf_PruningModel
    rank::T
    rank_window::T
    start_date::D
    end_date::D
end

function RankLeafPruningWindow(; rank, rank_window, start_date, duration=nothing, end_date=nothing)
    @assert !(isnothing(duration) && isnothing(end_date)) "Either `duration` or `end_date` must be given."

    if isnothing(end_date)
        end_date = start_date + duration
    end

    return RankLeafPruningWindow(promote(rank, rank_window)..., promote(start_date, end_date)...)
end

PlantSimEngine.inputs_(::RankLeafPruningWindow) = (rank=-9999, state="undetermined", biomass=-Inf, leaf_area=-Inf, state_phytomers=["undetermined"])
PlantSimEngine.outputs_(::RankLeafPruningWindow) = (litter_leaf=-Inf, pruning_decision="undetermined", is_pruned=false)

# Applied at the leaf scale:
function PlantSimEngine.run!(m::RankLeafPruningWindow, models, status, meteo, constants, extra=nothing)
    status.is_pruned && return # if the leaf is already pruned, no need to compute. Note that we don't use the state of the leaf here
    # because it may be pruned set to "Pruned" by the InfloStateModel, in which case the leaf is not really pruned yet.

    # Are we in the window of manual leaf pruning?
    is_theft_window = status.rank >= m.rank_window && meteo.date >= m.start_date && meteo.date <= m.end_date

    if status.rank > m.rank || status.state == "Pruned" || is_theft_window
        if is_theft_window
            status.pruning_decision = "Pruned during time window"
        elseif status.rank > m.rank
            status.pruning_decision = "Pruned at rank"
        else
            status.pruning_decision = "Pruned at bunch harvest"
        end

        status.leaf_area = 0.0
        status.litter_leaf = status.biomass
        status.biomass = 0.0
        status.reserve = 0.0
        status.state = "Pruned" # The leaf may not be pruned yet if it has a male inflorescence.
        status.is_pruned = true

        internode_node = parent(status.node)

        phytomer_node = parent(internode_node)
        # If the leaf is pruned but the phytomer is not harvested, then we harvest:
        phytomer_node[:plantsimengine_status].state = "Harvested"

        # Give the information to the inflorescence if any:
        internode_children = MultiScaleTreeGraph.children(internode_node)
        # Searching for male/female children, and if so, harvest them:
        inflo_nodes = filter(x -> MultiScaleTreeGraph.symbol(x) == "Female" || MultiScaleTreeGraph.symbol(x) == "Male", internode_children)
        if length(inflo_nodes) == 1
            inflo_nodes[1][:plantsimengine_status].state = "Harvested"
        end
    end
end