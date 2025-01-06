using XPalm, CSV, DataFrames, YAML
using CairoMakie, AlgebraOfGraphics
import PlantSimEngine: MultiScaleModel, PreviousTimeStep
using XPalm.Models
using PlantMeteo
using Dates
using Statistics

includet("mapping.jl")

meteo = CSV.read("0-data/Meteo_predictions_all_sites_cleaned.csv", DataFrame)
meteos = [Weather(i) for i in groupby(meteo, :Site)]

df_plot = transform(groupby(meteo, :Site), :Precipitations => cumsum => :cumulative_precipitations, :Tmin => cumsum => :Tmin_cumulative, :Tmax => cumsum => :Tmax_cumulative)
data(df_plot) * mapping(:date, :Precipitations, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_plot) * mapping(:date, :cumulative_precipitations, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_plot) * mapping(:date, :Tmin_cumulative, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_plot) * mapping(:date, :Tmax_cumulative, color=:Site => nonnumeric) * visual(Lines) |> draw()

begin
    params_default = YAML.load_file("0-data/xpalm_parameters.yml", dicttype=Dict{Symbol,Any})

    params_SMSE = copy(params_default)
    params_SMSE[:latitude] = 2.93416
    params_SMSE[:altitude] = 15.5

    params_PRESCO = copy(params_default)
    params_PRESCO[:latitude] = 6.137
    params_PRESCO[:altitude] = 15.5

    params_TOWE = copy(params_default)
    # params_TOWE[:latitude] = 7.65
    params_TOWE[:latitude] = 7.00
    params_TOWE[:altitude] = 15.5

    params = Dict("SMSE" => params_SMSE, "PR" => params_PRESCO, "TOWE" => params_TOWE,)

    out_vars = Dict{String,Any}(
        "Scene" => (:lai, :aPPFD),
        "Phytomer" => (:state,),
        "Leaf" => (:Rm, :TEff, :TT_since_init, :maturity, :potential_area, :carbon_demand, :carbon_allocation, :biomass, :final_potential_area, :increment_potential_area, :initiation_age, :leaf_area, :reserve, :rank, :state),
        "Internode" => (
            :Rm, :carbon_allocation, :carbon_demand, :potential_height, :potential_radius, :potential_volume, :biomass, :reserve,
            :final_potential_height, :final_potential_radius, :initiation_age, :TT_since_init, :final_potential_height, :final_potential_radius
        ),
        "Male" => (:Rm, :carbon_demand, :carbon_allocation, :biomass, :final_potential_biomass, :TEff),
        "Female" => (:Rm, :carbon_demand, :carbon_allocation, :biomass, :TEff, :fruits_number, :state, :carbon_demand_non_oil, :carbon_demand_oil, :carbon_demand_stalk, :biomass_fruits, :biomass_stalk, :TT_since_init),
        "Plant" => (
            :TEff, :plant_age, :ftsw, :biomass_bunch_harvested, :Rm, :aPPFD, :carbon_allocation, :biomass_bunch_harvested, :biomass_fruit_harvested,
            :carbon_assimilation, :reserve, :carbon_demand, :carbon_offer_after_allocation, :carbon_offer_after_rm, :leaf_area,
            :n_bunches_harvested, :biomass_bunch_harvested_cum, :n_bunches_harvested_cum, :TEff, :phytomer_count, :production_speed,
        ),
        "RootSystem" => (:Rm,),
        "Soil" => (:ftsw, :root_depth, :transpiration, :qty_H2O_C1, :qty_H2O_C2, :aPPFD),
    )

    simulations = DataFrame[]
    for m in meteos
        site = m[1].Site
        palm = XPalm.Palm(initiation_age=0, parameters=params[site])
        # sim = XPalm.PlantSimEngine.run!(palm.mtg, XPalm.model_mapping(palm), m, outputs=out_vars, executor=XPalm.PlantSimEngine.SequentialEx(), check=false)
        sim = XPalm.PlantSimEngine.run!(palm.mtg, xpalm_mapping(palm), m, outputs=out_vars, executor=XPalm.PlantSimEngine.SequentialEx(), check=false)

        df = XPalm.PlantSimEngine.outputs(sim, DataFrame, no_value=missing)
        df[!, "Site"] .= site
        push!(simulations, df)
    end

    # Adding the dates to the simulations:
    dfs_all = vcat(simulations...)
    dfs_all = leftjoin(dfs_all, meteo, on=[:Site, :timestep,])
    sort!(dfs_all, [:Site, :timestep])
end

dfs_scene = filter(row -> row[:organ] == "Scene", dfs_all)
dfs_scene_months = combine(groupby(dfs_scene, [:Site, :months_after_planting]), :lai => mean => :lai)
p_lai = data(dfs_scene_months) * mapping(:months_after_planting, :lai, color=:Site => nonnumeric) * visual(Lines)
draw(p_lai)

data(dfs_scene) * mapping(:timestep, :aPPFD => "Absorbed PPFD (MJ m⁻²[soil] d⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()

dfs_plant = filter(row -> row[:organ] == "Plant", dfs_all)
dfs_plant_month = combine(
    groupby(dfs_plant, [:Site, :months_after_planting]),
    :biomass_bunch_harvested => sum => :biomass_bunch_harvested_monthly,
    :biomass_bunch_harvested_cum => last => :biomass_bunch_harvested_cum,
    :n_bunches_harvested => sum => :n_bunches_harvested_monthly,
    :n_bunches_harvested_cum => last => :n_bunches_harvested_cum,
    :phytomer_count => last => :phytomer_count,
    :phytomer_count => (x -> x[end] - x[1]) => :phytomer_emmitted,
)

data(dfs_plant_month) * mapping(:months_after_planting, :phytomer_emmitted, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! n leaves should be around 150 at 100MAP, 200-250 at 150MAP
data(dfs_plant_month) * mapping(:months_after_planting, :phytomer_count, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :production_speed, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :TEff, color=:Site => nonnumeric) * visual(Lines) |> draw()


data(dfs_plant) * mapping(:timestep, :carbon_assimilation, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :Rm, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :aPPFD => "Absorbed PPFD (mol[PAR] plant⁻¹ d⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, (:aPPFD, :plant_leaf_area) => ((x, y) -> x / y) => "Absorbed PPFD (mol[PAR] m⁻²[leaf] d⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :plant_leaf_area, color=:Site => nonnumeric) * visual(Lines) |> draw()

data(combine(groupby(filter(row -> row[:organ] == "Leaf", dfs_all), [:Site, :timestep]), :leaf_area => sum => :leaf_area)) *
mapping(:timestep, :leaf_area => (x -> isinf(x) ? 0.0 : x) => "leaf_area", color=:Site => nonnumeric) * visual(Lines) |> draw()


data(combine(groupby(filter(row -> row[:organ] == "Female", dfs_all), [:Site, :timestep]), :Rm => sum => :Rm)) *
mapping(:timestep, :Rm => (x -> isinf(x) ? 0.0 : x) => "Rm", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(combine(groupby(filter(row -> row[:organ] == "Leaf", dfs_all), [:Site, :timestep]), :Rm => sum => :Rm)) *
mapping(:timestep, :Rm => (x -> isinf(x) ? 0.0 : x) => "Rm", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(combine(groupby(filter(row -> row[:organ] == "Male", dfs_all), [:Site, :timestep]), :Rm => sum => :Rm)) *
mapping(:timestep, :Rm => (x -> isinf(x) ? 0.0 : x) => "Rm", color=:Site => nonnumeric) * visual(Lines) |> draw()


data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, (:carbon_assimilation, :Rm) => ((x, y) -> y / x) => "Respiration Factor", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, (:carbon_assimilation, :plant_leaf_area) => ((x, y) -> y / x) => "A (gc m-2 leaf)", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, (:carbon_offer_after_rm, :carbon_demand) => ((x, y) -> x / y) => "Trophic state", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 3000, dfs_plant)) * mapping(:timestep, (:carbon_offer_after_rm, :carbon_demand) => ((x, y) -> x / y) => "Trophic state", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :carbon_offer_after_rm, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :carbon_demand, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! Carbon reserve, should be around 80kg at 10-12 years old:
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :reserve => (x -> x * 1e-3), color=:Site => nonnumeric) * visual(Lines) |> draw()

CC_Fruit = 0.4857     # Fruit carbon content (gC g-1 dry mass)
# Monthly harvest in kg dry mass per plant:
data(dfs_plant) * mapping(:timestep, :biomass_bunch_harvested => (x -> x * 1e-3 / CC_Fruit) => "Biomass Bunch Harvested (kg dry mass)", color=:Site => nonnumeric) * visual(Scatter) |> draw()
#! should be around 10kg for TOWE, 15-20kg for PR and 20kg for SMSE at 150MAP

data(dfs_plant) * mapping(:timestep, :biomass_fruit_harvested => (x -> x * 1e-3 / CC_Fruit) => "Biomass Fruit Harvested (kg dry mass)", color=:Site => nonnumeric) * visual(Scatter) |> draw()

CC_Fruit = 0.4857     # Fruit carbon content (gC g-1 dry mass)
# Monthly harvest in kg fresh mass per plant (assuming 30% water content):
data(dfs_plant) * mapping(:timestep, :biomass_bunch_harvested_cum => (x -> (x * 1e-3 / CC_Fruit) * 1.3) => "Cumulated FFB (kg tree⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
#! should be around 500 for TOWE, 1000 for PR and 1500 for SMSE at 150MAP

data(dfs_plant_month) * mapping(:months_after_planting, :biomass_bunch_harvested_monthly, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant_month) * mapping(:months_after_planting, :n_bunches_harvested_monthly, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! Should be around 80-150 at 150 months after planting, 50-80 for TOWE
data(dfs_plant_month) * mapping(:months_after_planting, :n_bunches_harvested_cum, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! this is a good one!!
p_ffb = data(dfs_plant_month) * mapping(:months_after_planting, :biomass_bunch_harvested_cum => (x -> x * 1e-3 / CC_Fruit * 1.3) => "Cumulated FFB (kg tree⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
# save("2-output/FFB_cumulated.png", p_ffb)

dfs_soil = filter(row -> row[:organ] == "Soil", dfs_all)
data(dfs_soil) * mapping(:timestep, :ftsw, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :transpiration, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :root_depth, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :qty_H2O_C1, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :qty_H2O_C2, color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(row -> row[:organ] == "Female" && row.Site == "SMSE", dfs_all)) * mapping(:timestep, :Rm => (x -> isinf(x) ? 0.0 : x) => "Rm", marker=:Site => nonnumeric, color=:node => nonnumeric) * visual(Scatter) |> draw()

df_female = filter(row -> row[:organ] == "Female" && row.Site == "PR", dfs_all)

# df_female_1 = filter(row -> row[:node] == 191, df_female)
unique(df_female.node) |> print
df_female_1 = filter(row -> row[:node] == 510, df_female)
data(df_female_1) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :TT_since_init, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :biomass, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :biomass_fruits, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :biomass_stalk, color=:Site => nonnumeric) * visual(Scatter) |> draw()

data(df_female_1) * mapping(:timestep, :carbon_demand_non_oil, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :carbon_demand_oil, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :carbon_demand_stalk, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :fruits_number, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :carbon_allocation, color=:Site => nonnumeric) * visual(Scatter) |> draw()


sum(df_female_1.carbon_demand_non_oil) + sum(df_female_1.carbon_demand_oil)
sum(df_female_1.carbon_demand_stalk)
maximum(df_female_1.biomass)
sum(df_female_1.carbon_allocation)

sum(df_female_1.carbon_demand)

df_female_2 = filter(row -> row[:node] == 511, df_female)
data(df_female_2) * mapping(:timestep, :TT_since_init, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_2) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_2) * mapping(:timestep, :biomass, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_2) * mapping(:timestep, :biomass_fruits, color=:Site => nonnumeric) * visual(Scatter) |> draw()

scatter(df_female_1.timestep, df_female_1.carbon_demand, color=:green, markersize=3)
scatter(df_female_1.timestep, df_female_1.carbon_allocation, color=:green, markersize=3)

scatter(df_female_1.timestep, df_female_1.carbon_allocation ./ df_female_1.carbon_demand, color=:green, markersize=3)
df_female_1.Rm[1] = 0.0
scatter(df_female_1.timestep, df_female_1.Rm, color=:green, markersize=3)

df_female_other = filter(row -> row[:node] == 859, df_female)
scatter(df_female_other.timestep, df_female_other.Rm, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.carbon_demand, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.carbon_allocation, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.biomass, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.biomass_fruits, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.biomass_stalk, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.carbon_demand_non_oil, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.carbon_demand_oil, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.carbon_demand_stalk, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.fruits_number, color=:green, markersize=3)
data(df_female_other) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
sum(df_female_other.carbon_demand)
scatter(df_female_other.TT_since_init, df_female_other.fruits_number, color=:green, markersize=3)
1


df_leaf = filter(row -> row[:organ] == "Leaf", dfs_all)
#! control that the number of leaves at rank > 1 increases each step
df_leaves_rank_sup_1 = combine(groupby(df_leaf, [:Site, :timestep]), :rank => (r -> length(filter(x -> x > 0, r))) => :rank)
data(df_leaves_rank_sup_1) * mapping(:timestep, :rank, color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! control that the number of leaves Opened is steady at mature stage, and is == to rank_leaf_pruning parameter
df_leaves_opened = combine(
    groupby(df_leaf, [:Site, :timestep]),
    :state => (s -> length(filter(x -> x == "Opened", s))) => :leaves_opened,
    :state => (s -> length(filter(x -> x == "Pruned", s))) => :leaves_pruned,
    :state => (s -> length(filter(x -> x == "undetermined", s))) => :leaves_undetermined,
)
data(df_leaves_opened) * mapping(:timestep, :leaves_opened, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :leaves_pruned, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :leaves_undetermined, color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! Control that all leaves that are undetermined are also of rank <1
df_leaves_undetermined = filter(row -> row.state == "undetermined", df_leaf)
@test all(df_leaves_undetermined.rank .< 1)
df_leaves_pruned = filter(row -> row.state == "Pruned", df_leaf)
@test all(df_leaves_pruned.rank .> params_default[:rank_leaf_pruning] .|| df_leaves_pruned.TT_since_init .> params_default[:female][:TT_harvest])


minimum(df_leaf_TOWE_ts_end_pruned.rank)

df_leaf_TOWE = filter(row -> row.Site == "SMSE", df_leaf)
df_leaf_TOWE_ts_end = filter(row -> row.timestep == 4160, df_leaf_TOWE)
df_leaf_TOWE_ts_end_opened = filter(x -> x.state == "Opened", df_leaf_TOWE_ts_end)
df_leaf_TOWE_ts_end_undetermined = filter(x -> x.state == "undetermined", df_leaf_TOWE_ts_end)
df_leaf_TOWE_ts_end_pruned = filter(x -> x.state == "Pruned", df_leaf_TOWE_ts_end)



unique(df_leaf.node) |> print
df_leaf_one = filter(row -> row[:node] == 80, df_leaf)
data(df_leaf_one) * mapping(:timestep, :leaf_area, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaf_one) * mapping(:timestep, :leaf_state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(filter(row -> row.timestep > 500, df_leaf_one)) * mapping(:timestep, :rank, color=:Site => nonnumeric) * visual(Scatter) |> draw()


df_phytomer = filter(row -> row[:organ] == "Phytomer" && row.Site == "PR", dfs_all)
df_phytomer_other = filter(row -> row[:node] == 856, df_phytomer)
data(df_phytomer_other) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
scatter(df_phytomer.timestep, df_phytomer.rank, color=:green, markersize=3)


TT_flowering = 6300.0
duration_fruit_setting = 405.0
TT_druit_number = TT_flowering + duration_fruit_setting
TT_harvest = 12150.0




df_phytomer = filter(row -> row[:organ] == "Phytomer", df)
scatter(df_phytomer.timestep, df_phytomer.rank, color=:green, markersize=3)

filter(row -> row.node == 6, df_phytomer) |>
(x -> data(x) * mapping(:timestep, :rank, color=:node => nonnumeric) * visual(Lines)) |>
draw()

scatter(filter(x -> x.node == 699, df_phytomer).rank)
print(filter(x -> x.node == 699, df_phytomer).rank)

df_scene = filter(row -> row[:organ] == "Scene", df)
df_scene.date = meteo.date
df_scene.yearmonth = [Date(Dates.yearmonth(d)...) for d in df_scene.date]
# Computes the index of the month since the beginning of the simulation:
df_scene.months_after_planting = groupindices(groupby(df_scene, :yearmonth))

scatter(df_scene.timestep, df_scene.lai, color=:green, markersize=3)
maximum(df_scene.lai)

scatter(df_scene.lai[365*10:min(365 * 12, length(df_scene.lai))])

df_plant = filter(row -> row[:organ] == "Plant", df)
df_plant.date = meteo.date
df_plant.yearmonth = [Date(Dates.yearmonth(d)...) for d in df_plant.date]
# Computes the index of the month since the beginning of the simulation:
df_plant.months_after_planting = groupindices(groupby(df_plant, :yearmonth))

scatter(df_plant.timestep, df_plant.plant_leaf_area, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.aPPFD, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_assimilation, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.Rm, color=:green, markersize=3)

scatter(df_plant.timestep, df_plant.carbon_demand, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_allocation, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.reserve, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_offer_after_allocation, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_offer_after_rm, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_demand, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_offer_after_rm - df_plant.carbon_demand, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.Rm ./ df_plant.carbon_assimilation, color=:green, markersize=3)
scatter(df_plant.date, df_plant.biomass_bunch_harvested, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.biomass_fruit_harvested, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.n_bunches_harvested, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.biomass_bunch_harvested_cum, color=:green, markersize=3)

# Monthly harvest:
df_scene_month = combine(groupby(df_scene, :yearmonth), :lai => mean => :lai, :months_after_planting => unique => :months_after_planting)
df_plant_month = combine(groupby(df_plant, :yearmonth), :biomass_bunch_harvested => sum => :biomass_bunch_harvested_monthly, :months_after_planting => unique => :months_after_planting)
CC_Fruit = 0.4857     # Fruit carbon content (gC g-1 dry mass)
# Monthly harvest in kg dry mass per plant:
lines(df_plant_month.yearmonth, df_plant_month.biomass_bunch_harvested_monthly ./ 1000 ./ CC_Fruit, color=:black)
lines(df_plant_month.months_after_planting, df_plant_month.biomass_bunch_harvested_monthly ./ 1000 ./ CC_Fruit, color=:black)
lines(df_scene_month.months_after_planting, df_scene_month.lai, color=:black)

df_internode = filter(row -> row[:organ] == "Internode", df)
df_internode_7 = filter(row -> row[:node] == 7, df_internode)
df_internode_one = filter(row -> row[:node] == 852, df_internode)

scatter(df_internode_7.carbon_demand)
scatter(df_internode_7.Rm)
scatter(df_internode_7.biomass)
sum(df_internode_7.carbon_demand)
df_internode_7.TT_since_init[1]
df_internode_7.initiation_age[1]
df_internode_7.reserve[1]
df_internode_7.biomass[1]


combine(groupby(df_internode, :timestep), :carbon_demand => sum)

reserves_trunk = combine(groupby(df_internode, :timestep), :reserve => sum) ./ 1000
lines(reserves_trunk.reserve_sum)
lines(reserves_trunk[365*10:min(365 * 12, nrow(reserves_trunk)), :].reserve_sum)



scatter(df_internode_one.timestep, df_internode_one.potential_height, color=:green, markersize=3)
scatter(df_internode_one.timestep, df_internode_one.potential_radius, color=:green, markersize=3)
scatter(df_internode_one.timestep, df_internode_one.potential_volume, color=:green, markersize=3)
scatter(df_internode_one.timestep, df_internode_one.carbon_demand, color=:green, markersize=3)
sum(df_internode_one.carbon_demand)
scatter(df_internode_one.timestep, df_internode_one.carbon_allocation, color=:green, markersize=3)
scatter(df_internode_one.timestep, df_internode_one.biomass .* 0.0017950000000000002, color=:green, markersize=3)
scatter(df_internode_one.Rm[2:end], color=:green, markersize=3)


df_leaf = filter(row -> row[:organ] == "Leaf", dfs_all)

# Count the number of occurence of each leaf state:
combine(groupby(filter(row -> row.timestep == 4291, df_leaf), :leaf_state), :leaf_state => length)

filter(row -> row.timestep == 4291, df_leaf)
sum(filter(row -> row.timestep == 4291, df_leaf).leaf_area)

sum(filter(row -> row.timestep == 4291 && row.leaf_state == "undetermined", df_leaf).leaf_area)

sum(filter(row -> row.timestep == 2190, df_leaf).leaf_area)
df_plant.plant_leaf_area[1460]


df_leaf_8 = filter(row -> row[:node] == 8, df_leaf)
scatter(df_leaf_8.carbon_demand)
scatter(df_leaf_8.rank)
df_leaf_8.reserve

df_leaf_one = filter(row -> row[:node] == 853, df_leaf)
scatter(df_leaf_one.timestep, df_leaf_one.final_potential_area, color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.potential_area, color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.increment_potential_area, color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.carbon_demand, color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.carbon_allocation, color=:green, markersize=3)
scatter(df_leaf_one.timestep, [df_leaf_one.leaf_area...], color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.biomass, color=:green, markersize=3)
f, a, plt = scatter(df_leaf_one.timestep, df_leaf_one.reserve, color=:green, markersize=3)
scatter!(a, df_leaf_one.timestep, df_leaf_one.biomass, markersize=3)
f

df_male = filter(row -> row[:organ] == "Male", df)
df_male_1 = filter(row -> row[:node] == 193, df_male)

scatter(df_male_1.timestep, df_male_1.TEff, color=:green, markersize=3)
scatter(df_male_1.timestep, df_male_1.final_potential_biomass, color=:green, markersize=3)
scatter(df_male_1.timestep, df_male_1.carbon_demand, color=:green, markersize=3)
scatter(df_male_1.timestep, df_male_1.carbon_allocation, color=:green, markersize=3)

df_female = filter(row -> row[:organ] == "Female", df)
df_female_1 = filter(row -> row[:node] == 189, df_female)
scatter(df_female_1.timestep, df_female_1.carbon_demand, color=:green, markersize=3)
scatter(df_female_1.timestep, df_female_1.carbon_allocation, color=:green, markersize=3)

df_female_other = filter(row -> row[:node] == 858, df_female)
scatter(df_female_other.timestep, df_female_other.carbon_demand, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.carbon_allocation, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.biomass, color=:green, markersize=3)
sum(df_female_other.carbon_demand)

# Using a notebook instead:
using Pluto, XPalm
XPalm.notebook("xpalm_notebook.jl")