### A Pluto.jl notebook ###
# v0.20.3

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ f8a57cfe-960e-11ef-3974-3d60ebc34f7b
begin
    import Pkg
    # activate a temporary environment
    Pkg.activate(mktempdir())
    Pkg.develop([Pkg.PackageSpec(url="https://github.com/PalmStudio/XPalm.jl")])
    Pkg.add([
        #Pkg.PackageSpec(url="https://github.com/PalmStudio/XPalm.jl", rev="main"),
        Pkg.PackageSpec(name="PlantSimEngine"),
        Pkg.PackageSpec(name="CairoMakie"),
        Pkg.PackageSpec(name="AlgebraOfGraphics"),
        Pkg.PackageSpec(name="PlantMeteo"),
        Pkg.PackageSpec(name="DataFrames"),
        Pkg.PackageSpec(name="CSV"),
        Pkg.PackageSpec(name="Statistics"),
        Pkg.PackageSpec(name="Dates"),
        Pkg.PackageSpec(name="YAML"),
        Pkg.PackageSpec(name="PlutoHooks"),
        Pkg.PackageSpec(name="PlutoLinks"),
        Pkg.PackageSpec(name="PlutoUI"),
        Pkg.PackageSpec(name="HypertextLiteral"),
    ])
end

# ╔═╡ 5dfdc85c-5f5a-48fc-a308-d205f862fb27
begin
    using PlantMeteo, DataFrames, CSV, Statistics, Dates, XPalm, YAML, PlantSimEngine
    using PlutoHooks, PlutoLinks, PlutoUI
    using HypertextLiteral
    using CairoMakie, AlgebraOfGraphics
end

# ╔═╡ 77aae20b-6310-4e34-8599-e08d01b28c9f
md"""
## Install

Installing packages
"""

# ╔═╡ 7fc8085f-fb74-4171-8df1-527ee1edfa73
md"""
## Import data

- Meteorology
"""

# ╔═╡ 1fa0b119-26fe-4807-8aea-50cdbd591656
meteo = let
    m = CSV.read(joinpath(dirname(dirname(pathof(XPalm))), "0-data/Meteo_Indonesia_SMSE.txt"), DataFrame)
    m.duration = [Dates.Day(i[1:1]) for i in m.duration]
    #Weather(m)
    m
end

# ╔═╡ 7165746e-cc57-4392-bb6b-705cb7221c24
md"""
- Model parameters
"""

# ╔═╡ 73f8cf85-cb03-444e-bf9e-c65363e9ffb8
params = let
    file = joinpath("xpalm_parameters.yml")
    update_time_ = PlutoLinks.@use_file_change(file)
    @use_memo([update_time_]) do
        YAML.load_file(file, dicttype=Dict{Symbol,Any})
    end
end

# ╔═╡ 9ec6a0fc-cbe2-4710-a366-6d78173d0379
md"""
- Model run:
"""

# ╔═╡ d6b7618a-c48e-404a-802f-b13c98257308
md"""
## Plotting all variables
"""

# ╔═╡ 387ee199-3f98-4c4a-9399-4bafe5f5243e
md"""
## Plotting one variable
"""

# ╔═╡ 460efc79-762c-4e97-b2dd-06afe83dfe8e
md"""
Choose one variable per scale:
"""

# ╔═╡ 5997198e-c8c4-494c-b904-bf54ae69e7e5
md"""
# References
"""

# ╔═╡ 1dbed83e-ec41-4daf-b398-4089e66b9842
function multiscale_variables_display(vars, Child, input_function, default)
    var_body = []
    for (key, values) in vars
        variable_names = sort(collect(values), by=x -> string(x) |> lowercase)
        length(variable_names) == 0 && continue
        Dict("Soil" => (:ftsw,), "Scene" => (:lai,), "Plant" => (:plant_leaf_area, :Rm, :aPPFD, :biomass_bunch_harvested_organs), "Leaf" => (:leaf_area,))
        default_at_scale = [get(default, key, ())...]

        push!(var_body,
            @htl("""
            <div style="display: inline-flex; flex-direction: column; padding: 5px 10px; margin: 5px; border: 1px solid #ddd; border-radius: 5px; box-shadow: 1px 1px 3px rgba(0, 0, 0, 0.1);">
                     <h3 style="margin: 0 0 5px 0; font-size: 1em;">$key</h3>
            	$(Child(key, input_function(variable_names, default_at_scale)))
            </div>
            """)
        )
    end

    return var_body
end

# ╔═╡ 96737f48-5478-4fbc-b72b-1ca33efa4846
function variables_display(vars; input_function=(x, default) -> PlutoUI.MultiCheckBox(x, orientation=:row, default=default), default=Dict())
    PlutoUI.combine() do Child
        @htl("""
        <div>
        	<div style="display: flex; flex-wrap: wrap; gap: 0px;">
        	    $(multiscale_variables_display(vars, Child, input_function, default))
        	</div>
        </div>
        """)
    end
end

# ╔═╡ bde1793e-983a-47e4-94a6-fbbe53fe72d6
@bind multiscale_variables variables_display(
    Dict(k => keys(merge(v...)) for (k, v) in PlantSimEngine.variables(XPalm.model_mapping(XPalm.Palm()))),
    default=Dict("Soil" => (:ftsw,), "Scene" => (:lai,), "Plant" => (:plant_leaf_area, :Rm, :aPPFD, :biomass_bunch_harvested), "Leaf" => (:leaf_area,))
)

# ╔═╡ 9bdd9351-c883-492f-adcc-062537fb9ecc
variables_dict = filter(x -> length(last(x)) > 0, Dict{String,Any}(zip(string.(keys(multiscale_variables)), [(i...,) for i in values(multiscale_variables)])))

# ╔═╡ d1377c41-98a8-491d-a4e5-d427e3cb7090
@bind variables_one variables_display(variables_dict; input_function=(x, default) -> Select(x, default=default))

# ╔═╡ bd6827a5-cc69-487a-be12-2793b3134db0
begin
    """
        InfloStateModelTheft(stem_apparent_density,respiration_cost)
        InfloStateModelTheft(stem_apparent_density=3000.0,respiration_cost=1.44)

    Give the phenological state to the phytomer and the inflorescence depending on thermal time since phytomer appearance

    # Arguments

    - `rank_theft`: rank below which all bunches are harvest by thieves.
    - `age_theft_start`: age of the plant when the period of theft starts (degree days).
    - `age_theft_end`: age of the plant when the period of theft ends (degree days).
    - `TT_flowering`: thermal time for flowering since phytomer appearence (degree days).
    - `duration_abortion`: duration used for computing abortion rate before flowering (degree days).
    - `duration_flowering_male`: duration between male flowering and senescence (degree days).
    - `duration_fruit_setting`: period of thermal time after flowering that determines the number of flowers in the bunch that become fruits, *i.e.* fruit set (degree days).
    - `TT_harvest`:Thermal time since phytomer appearance when the bunch is harvested (degree days)
    - `fraction_period_oleosynthesis`: fraction of the duration between flowering and harvesting when oleosynthesis occurs
    - `TT_ini_oleo`:thermal time for initializing oleosynthesis since phytomer appearence (degree days)

    # Inputs
    - `TT_since_init`: cumulated thermal time from the first day (degree C days)

    # Outputs 
    - `state`: phytomer state (undetermined,Aborted,Flowering,...)
    """
    struct InfloStateModelTheft{I,T} <: XPalm.AbstractStateModel
        rank_theft::I
        age_theft_start::I
        age_theft_end::I
        TT_flowering::T
        duration_abortion::T
        duration_flowering_male::T
        duration_fruit_setting::T
        TT_harvest::T
        fraction_period_oleosynthesis::T
        TT_ini_oleo::T
        TT_senescence_male::T
    end

    function InfloStateModelTheft(;
        rank_theft=25, age_theft_start=2190, age_theft_end=2373,
        TT_flowering=6300.0, duration_abortion=540.0, duration_flowering_male=1800.0, duration_fruit_setting=405.0, TT_harvest=12150.0, fraction_period_oleosynthesis=0.8,
        TT_senescence_male=TT_flowering + duration_flowering_male
    )
        duration_dev_bunch = TT_harvest - (TT_flowering + duration_fruit_setting)
        TT_ini_oleo = TT_flowering + duration_fruit_setting + (1 - fraction_period_oleosynthesis) * duration_dev_bunch
        InfloStateModelTheft(rank_theft, age_theft_start, age_theft_end, TT_flowering, duration_abortion, duration_flowering_male, duration_fruit_setting, TT_harvest, fraction_period_oleosynthesis, TT_ini_oleo, TT_senescence_male)
    end

    PlantSimEngine.inputs_(::InfloStateModelTheft) = (TT_since_init=-Inf, sex="undetermined", rank=-9999)
    PlantSimEngine.outputs_(::InfloStateModelTheft) = (state="undetermined", state_organs=["undetermined"],)
    PlantSimEngine.dep(::InfloStateModelTheft) = (abortion=XPalm.AbstractAbortionModel,)

    # At phytomer scale
    function PlantSimEngine.run!(m::InfloStateModelTheft, models, status, meteo, constants, extra=nothing)
        PlantSimEngine.run!(models.abortion, models, status, meteo, constants, extra)

        is_theft_window = status.rank == m.rank_theft && status.plant_age >= m.age_theft_start && status.plant_age <= m.age_theft_end

        if is_theft_window
            status.node[1][1][:plantsimengine_status].state = "Harvested"
        end

        status.state == "Aborted" && return # if the inflo is aborted, no need to compute 

        if status.sex == "Male"
            if status.TT_since_init > m.TT_senescence_male
                status.state = "Scenescent"
            elseif status.TT_since_init > m.TT_flowering
                status.state = "Flowering" #NB: if before TT_flowering it is undetermined
            end

            # Give the state to the reproductive organ (it is always the second child of the first child of the phytomer):
            status.node[1][2][:plantsimengine_status].state = status.state
        elseif status.sex == "Female"
            if is_theft_window || status.TT_since_init >= m.TT_harvest
                status.state = "Harvested"
                # Give the information to the leaf:
                status.node[1][1][:plantsimengine_status].state = "Harvested"
            elseif status.TT_since_init >= m.TT_ini_oleo
                status.state = "Oleosynthesis"
            elseif status.TT_since_init >= m.TT_flowering
                status.state = "Flowering"
            end
            # Else: status.state = "undetermined", but this is already the default value

            # Give the state to the reproductive organ:
            status.node[1][2][:plantsimengine_status].state = status.state
        end
    end

    InfloStateModelTheft
end

# ╔═╡ f7f30635-c2ed-4e78-bc91-aaad3a66e428
function model_mapping_theft(p)
    Dict(
        "Scene" => (
            XPalm.ET0_BP(),
            XPalm.DailyDegreeDays(),
            MultiScaleModel(
                model=XPalm.LAIModel(p.parameters[:scene_area]),
                mapping=[:leaf_area => ["Leaf"],],
            ),
            XPalm.Beer(k=p.parameters[:k]),
            XPalm.GraphNodeCount(length(p.mtg)), # to have the `graph_node_count` variable initialised in the status
        ),
        "Plant" => (
            MultiScaleModel(
                model=XPalm.DegreeDaysFTSW(
                    threshold_ftsw_stress=p.parameters[:phyllochron][:threshold_ftsw_stress],
                ),
                mapping=[:ftsw => "Soil",],
            ),
            XPalm.DailyPlantAgeModel(),
            XPalm.PhyllochronModel(
                p.parameters[:phyllochron][:age_palm_maturity],
                p.parameters[:phyllochron][:threshold_ftsw_stress],
                p.parameters[:phyllochron][:production_speed_initial],
                p.parameters[:phyllochron][:production_speed_mature],
            ),
            MultiScaleModel(
                model=XPalm.PlantLeafAreaModel(),
                mapping=[:leaf_area => ["Leaf"],],
            ),
            MultiScaleModel(
                model=XPalm.PhytomerEmission(p.mtg),
                mapping=[:graph_node_count => "Scene",],
            ),
            MultiScaleModel(
                model=XPalm.PlantRm(),
                mapping=[:Rm_organs => ["Leaf", "Internode", "Male", "Female"] .=> :Rm],
            ),
            MultiScaleModel(
                model=XPalm.SceneToPlantLightPartitioning(p.parameters[:scene_area]),
                mapping=[:aPPFD_scene => "Scene" => :aPPFD, :scene_leaf_area => "Scene"],
            ),
            XPalm.ConstantRUEModel(p.parameters[:RUE]),
            XPalm.CarbonOfferRm(),
            MultiScaleModel(
                model=XPalm.OrgansCarbonAllocationModel(p.parameters[:carbon_demand][:reserves][:cost_reserve_mobilization]),
                mapping=[
                    :carbon_demand_organs => ["Leaf", "Internode", "Male", "Female"] .=> :carbon_demand,
                    :carbon_allocation_organs => ["Leaf", "Internode", "Male", "Female"] .=> :carbon_allocation,
                    PreviousTimeStep(:reserve_organs) => ["Leaf", "Internode"] .=> :reserve,
                    PreviousTimeStep(:reserve)
                ],
            ),
            MultiScaleModel(
                model=XPalm.OrganReserveFilling(),
                mapping=[
                    :potential_reserve_organs => ["Internode", "Leaf"] .=> :potential_reserve,
                    :reserve_organs => ["Internode", "Leaf"] .=> :reserve,
                ],
            ),
            MultiScaleModel(
                model=XPalm.PlantBunchHarvest(),
                mapping=[
                    :biomass_bunch_harvested_organs => ["Female"] .=> :biomass_bunch_harvested,
                    :biomass_stalk_harvested_organs => ["Female"] .=> :biomass_stalk_harvested,
                    :biomass_fruit_harvested_organs => ["Female"] .=> :biomass_fruit_harvested,
                ],
            ),
        ),
        "Phytomer" => (
            MultiScaleModel(
                model=XPalm.InitiationAgeFromPlantAge(),
                mapping=[:plant_age => "Plant",],
            ),
            # DegreeDaysFTSW(
            #     threshold_ftsw_stress=p.parameters[:phyllochron][:threshold_ftsw_stress],
            # ), #! we should use this one instead of DailyDegreeDaysSinceInit I think
            MultiScaleModel(
                model=XPalm.DailyDegreeDaysSinceInit(),
                mapping=[:TEff => "Plant",], # Using TEff computed at plant scale
            ),
            MultiScaleModel(
                model=XPalm.SexDetermination(
                    TT_flowering=p.parameters[:inflo][:TT_flowering],
                    duration_abortion=p.parameters[:inflo][:duration_abortion],
                    duration_sex_determination=p.parameters[:inflo][:duration_sex_determination],
                    sex_ratio_min=p.parameters[:inflo][:sex_ratio_min],
                    sex_ratio_ref=p.parameters[:inflo][:sex_ratio_ref],
                    random_seed=p.parameters[:inflo][:random_seed],
                ),
                mapping=[
                    PreviousTimeStep(:carbon_offer_plant) => "Plant" => :carbon_offer_after_rm,
                    PreviousTimeStep(:carbon_demand_plant) => "Plant" => :carbon_demand,
                ],
            ),
            MultiScaleModel(
                model=XPalm.ReproductiveOrganEmission(p.mtg),
                mapping=[:graph_node_count => "Scene", :phytomer_count => "Plant"],
            ),
            MultiScaleModel(
                model=XPalm.AbortionRate(
                    TT_flowering=p.parameters[:inflo][:TT_flowering],
                    duration_abortion=p.parameters[:inflo][:duration_abortion],
                    abortion_rate_max=p.parameters[:inflo][:abortion_rate_max],
                    abortion_rate_ref=p.parameters[:inflo][:abortion_rate_ref],
                    random_seed=p.parameters[:inflo][:random_seed],
                ),
                mapping=[
                    PreviousTimeStep(:carbon_offer_plant) => "Plant" => :carbon_offer_after_rm,
                    PreviousTimeStep(:carbon_demand_plant) => "Plant" => :carbon_demand,
                ],
            ),
            MultiScaleModel(
                model=InfloStateModelTheft(
                    rank_theft=p.parameters[:inflo][:rank_theft],
                    age_theft_start=p.parameters[:inflo][:age_theft_start],
                    age_theft_end=p.parameters[:inflo][:age_theft_end],
                    TT_flowering=p.parameters[:inflo][:TT_flowering],
                    duration_abortion=p.parameters[:inflo][:duration_abortion],
                    duration_flowering_male=p.parameters[:male][:duration_flowering_male],
                    duration_fruit_setting=p.parameters[:female][:duration_fruit_setting],
                    TT_harvest=p.parameters[:female][:TT_harvest],
                    fraction_period_oleosynthesis=p.parameters[:female][:fraction_period_oleosynthesis],
                ), # Compute the state of the phytomer
                mapping=[:state_organs => ["Leaf", "Male", "Female"] .=> :state,],
                #! note: the mapping is artificial, we compute the state of those organs in the function directly because we use the status of a phytomer to give it to its children
                #! second note: the models should really be associated to the organs (female and male inflo + leaves)
            )
        ),
        "Internode" =>
            (
                MultiScaleModel(
                    model=XPalm.InitiationAgeFromPlantAge(),
                    mapping=[:plant_age => "Plant",],
                ),
                MultiScaleModel(
                    model=XPalm.DailyDegreeDaysSinceInit(),
                    mapping=[:TEff => "Plant",], # Using TEff computed at plant scale
                ),
                MultiScaleModel(
                    model=XPalm.RmQ10FixedN(
                        p.parameters[:respiration][:Internode][:Q10],
                        p.parameters[:respiration][:Internode][:Rm_base],
                        p.parameters[:respiration][:Internode][:T_ref],
                        p.parameters[:respiration][:Internode][:P_alive],
                        p.parameters[:nitrogen_content][:Internode],
                    ),
                    mapping=[PreviousTimeStep(:biomass),],
                ),
                XPalm.FinalPotentialInternodeDimensionModel(
                    p.parameters[:potential_dimensions][:age_max_height],
                    p.parameters[:potential_dimensions][:age_max_radius],
                    p.parameters[:potential_dimensions][:min_height],
                    p.parameters[:potential_dimensions][:min_radius],
                    p.parameters[:potential_dimensions][:max_height],
                    p.parameters[:potential_dimensions][:max_radius],
                ),
                XPalm.PotentialInternodeDimensionModel(
                    p.parameters[:potential_dimensions][:inflexion_point_height],
                    p.parameters[:potential_dimensions][:slope_height],
                    p.parameters[:potential_dimensions][:inflexion_point_radius],
                    p.parameters[:potential_dimensions][:slope_radius],
                ),
                XPalm.InternodeCarbonDemandModel(
                    p.parameters[:carbon_demand][:internode][:stem_apparent_density],
                    p.parameters[:carbon_demand][:internode][:respiration_cost]
                ),
                MultiScaleModel(
                    model=XPalm.PotentialReserveInternode(
                        p.parameters[:nsc_max]
                    ),
                    mapping=[PreviousTimeStep(:biomass), PreviousTimeStep(:reserve)],
                ),
                XPalm.InternodeBiomass(
                    initial_biomass=p.parameters[:potential_dimensions][:min_height] * p.parameters[:potential_dimensions][:min_radius] * p.parameters[:carbon_demand][:internode][:stem_apparent_density],
                    respiration_cost=p.parameters[:carbon_demand][:internode][:respiration_cost]
                ),
                XPalm.InternodeDimensionModel(p.parameters[:carbon_demand][:internode][:stem_apparent_density]),
            ),
        "Leaf" => (
            MultiScaleModel(
                model=XPalm.DailyDegreeDaysSinceInit(),
                mapping=[:TEff => "Plant",], # Using TEff computed at plant scale
            ),
            XPalm.FinalPotentialAreaModel(
                p.parameters[:potential_area][:age_first_mature_leaf],
                p.parameters[:potential_area][:leaf_area_first_leaf],
                p.parameters[:potential_area][:leaf_area_mature_leaf],
            ),
            XPalm.PotentialAreaModel(
                p.parameters[:potential_area][:inflexion_index],
                p.parameters[:potential_area][:slope],
            ),
            MultiScaleModel(
                model=XPalm.LeafStateModel(),
                mapping=[:rank_phytomers => ["Phytomer" => :rank], :state_phytomers => ["Phytomer" => :state],],
            ),
            MultiScaleModel(
                model=XPalm.LeafRankModel(),
                mapping=[:rank_phytomers => ["Phytomer" => :rank],],
            ),
            XPalm.RankLeafPruning(p.parameters[:rank_leaf_pruning]),
            MultiScaleModel(
                model=XPalm.InitiationAgeFromPlantAge(),
                mapping=[:plant_age => "Plant",],
            ),
            MultiScaleModel(
                model=XPalm.LeafAreaModel(
                    p.parameters[:lma_min],
                    p.parameters[:leaflets_biomass_contribution],
                    p.parameters[:potential_area][:leaf_area_first_leaf],
                ),
                mapping=[PreviousTimeStep(:biomass),],
            ),
            MultiScaleModel(
                model=XPalm.RmQ10FixedN(
                    p.parameters[:respiration][:Leaf][:Q10],
                    p.parameters[:respiration][:Leaf][:Rm_base],
                    p.parameters[:respiration][:Leaf][:T_ref],
                    p.parameters[:respiration][:Leaf][:P_alive],
                    p.parameters[:nitrogen_content][:Leaf]
                ),
                mapping=[PreviousTimeStep(:biomass),],
            ),
            XPalm.LeafCarbonDemandModelPotentialArea(
                p.parameters[:lma_min],
                p.parameters[:carbon_demand][:leaf][:respiration_cost],
                p.parameters[:leaflets_biomass_contribution]
            ),
            MultiScaleModel(
                model=XPalm.PotentialReserveLeaf(
                    p.parameters[:lma_min],
                    p.parameters[:lma_max],
                    p.parameters[:leaflets_biomass_contribution]
                ),
                mapping=[PreviousTimeStep(:leaf_area), PreviousTimeStep(:reserve)],
            ),
            XPalm.LeafBiomass(
                initial_biomass=p.parameters[:potential_area][:leaf_area_first_leaf] * p.parameters[:lma_min] /
                                p.parameters[:leaflets_biomass_contribution],
                respiration_cost=p.parameters[:carbon_demand][:leaf][:respiration_cost],
            ),
        ),
        "Male" => (
            MultiScaleModel(
                model=XPalm.InitiationAgeFromPlantAge(),
                mapping=[:plant_age => "Plant",],
            ),
            MultiScaleModel(
                model=XPalm.DailyDegreeDaysSinceInit(),
                mapping=[:TEff => "Plant",], # Using TEff computed at plant scale
            ),
            XPalm.MaleFinalPotentialBiomass(
                p.parameters[:male][:male_max_biomass],
                p.parameters[:male][:age_mature_male],
                p.parameters[:male][:fraction_biomass_first_male],
            ),
            MultiScaleModel(
                model=XPalm.RmQ10FixedN(
                    p.parameters[:respiration][:Male][:Q10],
                    p.parameters[:respiration][:Male][:Rm_base],
                    p.parameters[:respiration][:Male][:T_ref],
                    p.parameters[:respiration][:Male][:P_alive],
                    p.parameters[:nitrogen_content][:Male],
                ),
                mapping=[PreviousTimeStep(:biomass),],
            ),
            XPalm.MaleCarbonDemandModel(
                p.parameters[:carbon_demand][:male][:respiration_cost],
                p.parameters[:inflo][:TT_flowering],
                p.parameters[:male][:duration_flowering_male],
            ),
            XPalm.MaleBiomass(
                p.parameters[:carbon_demand][:male][:respiration_cost],
            ),
        ),
        "Female" => (
            MultiScaleModel(
                model=XPalm.InitiationAgeFromPlantAge(),
                mapping=[:plant_age => "Plant",],
            ),
            MultiScaleModel(
                model=XPalm.DailyDegreeDaysSinceInit(),
                mapping=[:TEff => "Plant",],
            ),
            MultiScaleModel(
                model=XPalm.RmQ10FixedN(
                    p.parameters[:respiration][:Female][:Q10],
                    p.parameters[:respiration][:Female][:Rm_base],
                    p.parameters[:respiration][:Female][:T_ref],
                    p.parameters[:respiration][:Female][:P_alive],
                    p.parameters[:nitrogen_content][:Female],
                ),
                mapping=[PreviousTimeStep(:biomass),],
            ),
            XPalm.FemaleFinalPotentialFruits(
                p.parameters[:female][:age_mature_female],
                p.parameters[:female][:fraction_first_female],
                p.parameters[:female][:potential_fruit_number_at_maturity],
                p.parameters[:female][:potential_fruit_weight_at_maturity],
                p.parameters[:female][:stalk_max_biomass],
            ),
            MultiScaleModel(
                model=XPalm.NumberSpikelets(
                    TT_flowering=p.parameters[:inflo][:TT_flowering],
                    duration_dev_spikelets=p.parameters[:female][:duration_dev_spikelets],
                ),
                mapping=[PreviousTimeStep(:carbon_offer_plant) => "Plant" => :carbon_offer_after_rm, PreviousTimeStep(:carbon_demand_plant) => "Plant" => :carbon_demand],
            ),
            MultiScaleModel(
                model=XPalm.NumberFruits(
                    TT_flowering=p.parameters[:inflo][:TT_flowering],
                    duration_fruit_setting=p.parameters[:female][:duration_fruit_setting],
                ),
                mapping=[PreviousTimeStep(:carbon_offer_plant) => "Plant" => :carbon_offer_after_rm, PreviousTimeStep(:carbon_demand_plant) => "Plant" => :carbon_demand],
            ),
            XPalm.FemaleCarbonDemandModel(
                p.parameters[:carbon_demand][:female][:respiration_cost],
                p.parameters[:carbon_demand][:female][:respiration_cost_oleosynthesis],
                p.parameters[:inflo][:TT_flowering],
                p.parameters[:female][:TT_harvest],
                p.parameters[:female][:duration_fruit_setting],
                p.parameters[:female][:oil_content],
                p.parameters[:female][:fraction_period_oleosynthesis],
                p.parameters[:female][:fraction_period_stalk],
            ),
            XPalm.FemaleBiomass(
                p.parameters[:carbon_demand][:female][:respiration_cost],
                p.parameters[:carbon_demand][:female][:respiration_cost_oleosynthesis],
            ),
            XPalm.BunchHarvest(),
        ),
        "RootSystem" => (
            MultiScaleModel(
                model=XPalm.DailyDegreeDaysSinceInit(),
                mapping=[:TEff => "Scene",], # Using TEff computed at scene scale
            ),
        ),
        "Soil" => (
            # light_interception=Beer{Soil}(),
            MultiScaleModel(
                model=XPalm.FTSW(ini_root_depth=p.parameters[:ini_root_depth]),
                mapping=[:ET0 => "Scene", :aPPFD => "Scene"], # Using TEff computed at scene scale
            ),
            MultiScaleModel(
                model=XPalm.RootGrowthFTSW(ini_root_depth=p.parameters[:ini_root_depth]),
                mapping=[:TEff => "Scene",], # Using TEff computed at scene scale
            ),
        )
    )
end

# ╔═╡ 8bc0ac37-e34e-469b-9346-0231aa28be63
df = let
    p = XPalm.Palm(parameters=params)
    models = model_mapping_theft(p)
    if length(variables_dict) > 0
        out = PlantSimEngine.run!(p.mtg, models, meteo, outputs=variables_dict, executor=PlantSimEngine.SequentialEx(), check=false)
        df = PlantSimEngine.outputs(out, DataFrame, no_value=missing)
    end
end

# ╔═╡ a8c2f2f2-e016-494d-9f7b-c445c62b0810
dfs = Dict(i => select(filter(row -> row.organ == i, df), [:timestep, :node, variables_dict[i]...]) for i in keys(variables_dict));

# ╔═╡ f6ad8a2a-75ec-4f9b-a462-fccccf7f58e5
let
    htmlplots = []
    for (scale, df) in dfs
        n_nodes_scale = length(unique(dfs[scale].node))

        if n_nodes_scale == 1
            m = mapping(:timestep, :value, layout=:variable)
        else
            m = mapping(:timestep, :value, color=:node => nonnumeric, layout=:variable)
        end

        height_plot = max(300, 300 * length(variables_dict[scale]) / 2)

        plt = data(stack(dfs[scale], Not([:timestep, :node]), view=true)) * m * visual(Lines)

        pag = paginate(plt, layout=2)

        # info = htl"$scale"
        # p = draw(plt; figure=(;size=(800,height_plot)), facet=(;linkyaxes=:none))
        figuregrids = draw(pag; figure=(; size=(800, 300)), facet=(; linkxaxes=:none, linkyaxes=:none), legend=(; show=false))
        push!(htmlplots, htl"<h4>$scale:</h4>")
        for i in figuregrids
            push!(htmlplots, htl"<div>$i</div>")
        end
    end

    htl"<h5>Plots:</h5>$htmlplots"
end

# ╔═╡ 279a3e36-00c6-4506-a0a7-71e876aef781
@bind nodes variables_display(Dict(scale => unique(dfs[scale].node) for (scale, df) in dfs); input_function=(x, default) -> MultiSelect(x))

# ╔═╡ 462fc904-a5bc-4fc0-b342-166d2b02376c
let
    variables_one_dict = Dict(zip(string.(keys(variables_one)), values(variables_one)))
    nodes_dict = Dict(zip(string.(keys(nodes)), values(nodes)))
    htmlplots = []
    for (scale, df) in dfs
        n_nodes_scale = length(unique(dfs[scale].node))

        if n_nodes_scale == 1
            m = mapping(:timestep, variables_one_dict[scale])
            df_plot = select(dfs[scale], [:timestep, :node, variables_one_dict[scale]])
        else
            m = mapping(:timestep, variables_one_dict[scale], color=:node => nonnumeric)
            df_plot = select(df, [:timestep, :node, variables_one_dict[scale]])
            filter!(row -> row.node in nodes_dict[scale], df_plot)
        end

        height_plot = 300

        plt = data(df_plot) * m * visual(Lines)
        p = draw(plt; figure=(; size=(800, height_plot)))
        push!(htmlplots, htl"<h4>$scale:</h4>")
        push!(htmlplots, htl"<div>$p</div>")
    end

    htl"<h5>Plots:</h5>$htmlplots"
end

# ╔═╡ Cell order:
# ╟─77aae20b-6310-4e34-8599-e08d01b28c9f
# ╠═f8a57cfe-960e-11ef-3974-3d60ebc34f7b
# ╠═5dfdc85c-5f5a-48fc-a308-d205f862fb27
# ╟─7fc8085f-fb74-4171-8df1-527ee1edfa73
# ╠═1fa0b119-26fe-4807-8aea-50cdbd591656
# ╟─7165746e-cc57-4392-bb6b-705cb7221c24
# ╠═73f8cf85-cb03-444e-bf9e-c65363e9ffb8
# ╟─9ec6a0fc-cbe2-4710-a366-6d78173d0379
# ╠═8bc0ac37-e34e-469b-9346-0231aa28be63
# ╟─bde1793e-983a-47e4-94a6-fbbe53fe72d6
# ╟─9bdd9351-c883-492f-adcc-062537fb9ecc
# ╟─a8c2f2f2-e016-494d-9f7b-c445c62b0810
# ╟─d6b7618a-c48e-404a-802f-b13c98257308
# ╟─f6ad8a2a-75ec-4f9b-a462-fccccf7f58e5
# ╟─387ee199-3f98-4c4a-9399-4bafe5f5243e
# ╟─460efc79-762c-4e97-b2dd-06afe83dfe8e
# ╟─d1377c41-98a8-491d-a4e5-d427e3cb7090
# ╠═279a3e36-00c6-4506-a0a7-71e876aef781
# ╟─462fc904-a5bc-4fc0-b342-166d2b02376c
# ╟─5997198e-c8c4-494c-b904-bf54ae69e7e5
# ╟─96737f48-5478-4fbc-b72b-1ca33efa4846
# ╟─1dbed83e-ec41-4daf-b398-4089e66b9842
# ╟─bd6827a5-cc69-487a-be12-2793b3134db0
# ╟─f7f30635-c2ed-4e78-bc91-aaad3a66e428
