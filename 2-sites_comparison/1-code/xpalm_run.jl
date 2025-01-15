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
        "Phytomer" => (:state, :TEff, :TT_since_init),
        "Leaf" => (
            :Rm, :TEff, :TT_since_init, :maturity, :potential_area, :carbon_demand, :carbon_allocation, :biomass, :final_potential_area,
            :increment_potential_area, :initiation_age, :leaf_area, :reserve, :rank, :state, :pruning_decision
        ),
        "Internode" => (
            :Rm, :carbon_allocation, :carbon_demand, :potential_height, :potential_radius, :potential_volume, :biomass, :reserve,
            :final_potential_height, :final_potential_radius, :initiation_age, :TT_since_init, :final_potential_height, :final_potential_radius,
            :height, :radius,
        ),
        "Male" => (:Rm, :carbon_demand, :carbon_allocation, :biomass, :final_potential_biomass, :TEff),
        "Female" => (
            :Rm, :carbon_demand, :carbon_allocation, :biomass, :TEff, :fruits_number, :state, :carbon_demand_non_oil, :carbon_demand_oil, :carbon_demand_stalk, :biomass_fruits,
            :biomass_stalk, :TT_since_init, :biomass_bunch_harvested
        ),
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

#! Scene scale
dfs_scene = filter(row -> row[:organ] == "Scene", dfs_all)
select!(dfs_scene, findall(x -> any(!ismissing(i) for i in x), eachcol(dfs_scene)))
dfs_scene_months = combine(groupby(dfs_scene, [:Site, :months_after_planting]), :lai => mean => :lai)
p_lai = data(dfs_scene_months) * mapping(:months_after_planting, :lai, color=:Site => nonnumeric) * visual(Lines)
draw(p_lai)

data(dfs_scene) * mapping(:timestep, :aPPFD => "Absorbed PPFD (MJ m⁻²[soil] d⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()


#! Plant scale
dfs_plant = filter(row -> row[:organ] == "Plant", dfs_all)
select!(dfs_plant, findall(x -> any(!ismissing(i) for i in x), eachcol(dfs_plant)))
# combine(groupby(dfs_plant, :Site), :TEff => sum => :TEff)

dfs_plant_month = combine(
    groupby(dfs_plant, [:Site, :months_after_planting]),
    :date => (x -> Date(yearmonth(x[1])...)) => :date,
    :TEff => sum => :TEff,
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass_bunch_harvested => sum => :biomass_bunch_harvested_monthly,
    :biomass_bunch_harvested => mean => :average_biomass_bunch_harvested_monthly,
    :biomass_bunch_harvested_cum => last => :biomass_bunch_harvested_cum,
    :n_bunches_harvested => sum => :n_bunches_harvested_monthly,
    :n_bunches_harvested_cum => last => :n_bunches_harvested_cum,
    :phytomer_count => last => :phytomer_count,
    :phytomer_count => (x -> x[end] - x[1]) => :phytomer_emmitted,
)

dfs_plant_year = combine(
    groupby(transform(dfs_plant, :date => ByRow(year) => :year), [:Site, :year]),
    :TEff => sum => :TEff,
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass_bunch_harvested => sum => :biomass_bunch_harvested,
)


data(dfs_plant_month) * mapping(:months_after_planting, :phytomer_emmitted, color=:Site => nonnumeric) * visual(Lines) |> draw()

# Observations of emitted leaves:
nb_leaves_emitted_obs = CSV.read("0-data/validation/phyllochron_observations.csv", DataFrame)
sort!(nb_leaves_emitted_obs, [:site, :genotype, :months_after_planting])
transform!(groupby(nb_leaves_emitted_obs, [:site, :genotype]), :nb_leaves_emitted => cumsum => :nb_leaves_emitted_cum)

nb_leaves_emitted_obs = leftjoin(nb_leaves_emitted_obs, select(dfs_plant_month, :Site, :date, :TEff, :phytomer_emmitted => :nb_leaves_emitted_sim), on=[:site => :Site, :date])
dropmissing!(nb_leaves_emitted_obs)
transform!(groupby(nb_leaves_emitted_obs, [:site, :genotype]), :nb_leaves_emitted_sim => cumsum => :nb_leaves_emitted_cum_sim, [:nb_leaves_emitted, :TEff] => ((x, y) -> x ./ y) => :nb_leaves_emitted_per_TEff)

data(nb_leaves_emitted_obs) * mapping(:months_after_planting, :nb_leaves_emitted, color=:genotype, layout=:site) * visual(Lines) |> draw()
data(nb_leaves_emitted_obs) * mapping(:months_after_planting, :nb_leaves_emitted_cum, color=:genotype, layout=:site) * visual(Lines) |> draw()
data(nb_leaves_emitted_obs) * mapping(:months_after_planting, :nb_leaves_emitted_per_TEff, color=:genotype, layout=:site) * visual(Lines) |> draw()
# data(nb_leaves_emitted_obs) * mapping(:months_after_planting, :nb_leaves_emitted_cum_sim, color=:genotype, layout=:site) * visual(Lines) |> draw()
data(nb_leaves_emitted_obs) * mapping(:months_after_planting, (:nb_leaves_emitted, :TEff) => ((x, y) -> x / y) => "nb_leaves_emitted_per_TEff", color=:site) * visual(Scatter) |> draw()

#! Computing the phyllochron (production speed) for each site at 50 and 100MAP:
phylochron_MAP50 = combine(groupby(filter(row -> row.months_after_planting < 50, nb_leaves_emitted_obs), :site), :nb_leaves_emitted_per_TEff => mean => :nb_leaves_emitted_per_TEff)
phylochron_MAP100 = combine(groupby(filter(row -> row.months_after_planting > 100, nb_leaves_emitted_obs), :site), :nb_leaves_emitted_per_TEff => mean => :nb_leaves_emitted_per_TEff)
# Computing the average over all sites, that we use in the parameter file.
mean(phylochron_MAP50.nb_leaves_emitted_per_TEff), mean(phylochron_MAP100.nb_leaves_emitted_per_TEff)
#! note: the phyllochron seems to be affected by stress, as it is lower in SMSE and even lower in TOWE compared to PR.

# Computing the number of leaves emitted between 50 and 100MAP:
leaves_emitted_50MAP_100MAP = leftjoin(
    filter(row -> row.months_after_planting == 50, nb_leaves_emitted_obs),
    filter(row -> row.months_after_planting == 100, nb_leaves_emitted_obs),
    on=[:site, :genotype], renamecols="_50MAP" => "_100MAP"
) |> dropmissing!
nb_leaves_50_to_100MAP_obs = leaves_emitted_50MAP_100MAP.nb_leaves_emitted_cum_100MAP .- leaves_emitted_50MAP_100MAP.nb_leaves_emitted_cum_50MAP


df_phytomer_count = combine(groupby(dfs_plant_month, :Site), :months_after_planting => last, :phytomer_count => maximum, :TEff => sum, :nb_timesteps => sum, renamecols=false)
df_phytomer_count.phytomer_per_TT = df_phytomer_count.phytomer_count ./ df_phytomer_count.TEff
df_phytomer_count.phytomer_per_day = df_phytomer_count.phytomer_count ./ df_phytomer_count.nb_timesteps
df_phytomer_count.days_per_phytomer = df_phytomer_count.nb_timesteps ./ df_phytomer_count.phytomer_count

data(dfs_plant) * mapping(:timestep, :carbon_assimilation, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :Rm, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :aPPFD => "Absorbed PPFD (mol[PAR] plant⁻¹ d⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, (:aPPFD, :leaf_area) => ((x, y) -> x / y) => "Absorbed PPFD (mol[PAR] m⁻²[leaf] d⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :leaf_area, color=:Site => nonnumeric) * visual(Lines) |> draw()

data(combine(groupby(filter(row -> row[:organ] == "Leaf", dfs_all), [:Site, :timestep]), :leaf_area => sum => :leaf_area)) *
mapping(:timestep, :leaf_area => (x -> isinf(x) ? 0.0 : x) => "leaf_area", color=:Site => nonnumeric) * visual(Lines) |> draw()


data(combine(groupby(filter(row -> row[:organ] == "Female", dfs_all), [:Site, :timestep]), :Rm => sum => :Rm)) *
mapping(:timestep, :Rm => (x -> isinf(x) ? 0.0 : x) => "Rm", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(combine(groupby(filter(row -> row[:organ] == "Leaf", dfs_all), [:Site, :timestep]), :Rm => sum => :Rm)) *
mapping(:timestep, :Rm => (x -> isinf(x) ? 0.0 : x) => "Rm", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(combine(groupby(filter(row -> row[:organ] == "Male", dfs_all), [:Site, :timestep]), :Rm => sum => :Rm)) *
mapping(:timestep, :Rm => (x -> isinf(x) ? 0.0 : x) => "Rm", color=:Site => nonnumeric) * visual(Lines) |> draw()


data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, (:carbon_assimilation, :Rm) => ((x, y) -> y / x) => "Respiration Factor", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, (:carbon_assimilation, :leaf_area) => ((x, y) -> y / x) => "A (gc m-2 leaf)", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, (:carbon_offer_after_rm, :carbon_demand) => ((x, y) -> x / y) => "Trophic state", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 3000, dfs_plant)) * mapping(:timestep, (:carbon_offer_after_rm, :carbon_demand) => ((x, y) -> x / y) => "Trophic state", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :carbon_offer_after_rm, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :carbon_demand, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :Rm, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! Carbon reserve, should be around 80kg at 10-12 years old:
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :reserve => (x -> x * 1e-3), color=:Site => nonnumeric) * visual(Lines) |> draw()

CC_Fruit = 0.4857     # Fruit carbon content (gC g-1 dry mass)
water_content_mesocarp = 0.25  # Water content of the mesocarp
dry_to_fresh_ratio = 1 / (1 - water_content_mesocarp)  # Based on the mesocarp water content of 0.3

# Monthly harvest in kg dry mass per plant:
data(dfs_plant) * mapping(:timestep, :biomass_bunch_harvested => (x -> x * 1e-3 / CC_Fruit) => "Biomass Bunch Harvested (kg dry mass)", color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! should be around 10kg for TOWE, 15-20kg for PR and 20kg for SMSE at 150MAP
data(dfs_plant) * mapping(:timestep, :biomass_fruit_harvested => (x -> x * 1e-3 / CC_Fruit) => "Biomass Fruit Harvested (kg dry mass)", color=:Site => nonnumeric) * visual(Scatter) |> draw()

# Monthly harvest in kg fresh mass per plant (assuming 30% water content):
data(dfs_plant) * mapping(:months_after_planting, :biomass_bunch_harvested_cum => (x -> (x * 1e-3 / CC_Fruit) * dry_to_fresh_ratio) => "Cumulated FFB (kg tree⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
#! should be around 500 for TOWE, 1000 for PR and 1500 for SMSE at 150MAP

data(dfs_plant_month) * mapping(:months_after_planting, :biomass_bunch_harvested_monthly, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant_month) * mapping(:months_after_planting, :n_bunches_harvested_monthly, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant_month) * mapping(:months_after_planting, :average_biomass_bunch_harvested_monthly => (x -> (x * 1e-3 / CC_Fruit) * dry_to_fresh_ratio) => "Average biomass bunch (kg tree⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()


#! Should be around 80-150 at 150 months after planting, 50-80 for TOWE
data(dfs_plant_month) * mapping(:months_after_planting, :n_bunches_harvested_cum, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! this is a good one!! It should be around 100kg for PR, 750 for SMSE and 250 for TOWE at 100 MAP
p_ffb = data(dfs_plant_month) * mapping(:months_after_planting, :biomass_bunch_harvested_cum => (x -> x * 1e-3 / CC_Fruit * dry_to_fresh_ratio) => "Cumulated FFB (kg tree⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
# save("2-output/FFB_cumulated.png", p_ffb)

#! FFB in kg plant-1 year-1 should be around 100-200 kg according to Van Kraalingen et al. 1989 (may be way higher now):
p_ffb_year_plant = data(dfs_plant_year) * mapping(:year, :biomass_bunch_harvested => (x -> x * 1e-3 / CC_Fruit * dry_to_fresh_ratio) => "FFB (kg plant⁻¹ year⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
#! FFB (yield, t ha-1):
p_ffb_year_plot = data(dfs_plant_year) * mapping(:year, :biomass_bunch_harvested => (x -> x * 1e-6 / CC_Fruit * dry_to_fresh_ratio / params_default[:scene_area] * 10000) => "FFB (t ha⁻¹ year⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()


dfs_soil = filter(row -> row[:organ] == "Soil", dfs_all)
select!(dfs_soil, findall(x -> any(!ismissing(i) for i in x), eachcol(dfs_soil)))
data(dfs_soil) * mapping(:timestep, :ftsw, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :transpiration, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :root_depth, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :qty_H2O_C1, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :qty_H2O_C2, color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(row -> row[:organ] == "Female" && row.Site == "SMSE", dfs_all)) * mapping(:timestep, :Rm => (x -> isinf(x) ? 0.0 : x) => "Rm", marker=:Site => nonnumeric, color=:node => nonnumeric) * visual(Scatter) |> draw()


#! Females (bunches)
df_female = filter(row -> row[:organ] == "Female" && row.Site == "PR", dfs_all)
select!(df_female, findall(x -> any(!ismissing(i) for i in x), eachcol(df_female)))

# df_female_1 = filter(row -> row[:node] == 191, df_female)


df_female_month = combine(
    groupby(df_female, [:Site, :months_after_planting]),
    :date => (x -> Date(yearmonth(x[1])...)) => :date,
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :state => (x -> sum(x .== "Harvested")) => :n_bunches_harvested,
    :biomass_bunch_harvested => sum => :biomass_bunch_harvested,
    :biomass_bunch_harvested => (x -> mean(filter(y -> y > 0, x))) => :biomass_bunch_harvested_average,
)

data(df_female_month) * mapping(:months_after_planting, :biomass_bunch_harvested_average, color=:Site => nonnumeric) * visual(Lines) |> draw()

data(df_female_month) * mapping(:months_after_planting, :biomass_bunch_harvested_average => (x -> (x * 1e-3 / CC_Fruit) * dry_to_fresh_ratio) => "Average bunch biomass (kg)", color=:Site => nonnumeric) * visual(Scatter) |> draw()

data(df_female) * mapping(:timestep, :fruits_number => (x -> x > 0 ? x : 0) => "Number of fruits", color=:Site => nonnumeric, marker=:node => nonnumeric) * visual(Scatter) |> draw()


data(filter(x -> x.Site == "PR", df_female)) * mapping(:months_after_planting, :fruits_number => (x -> x > 0 ? x : 0) => "Number of fruits", color=:node => nonnumeric) * visual(Scatter) |> draw()


# coeff = XPalm.age_relative_value.(1:length(meteos[1]), params_default[:female][:days_increase_number_fruits], params_default[:female][:days_maximum_number_fruits], params_default[:female][:fraction_first_female], 1.0)
#! Calibration of the number of fruits:
days_increase_number_fruits = 2379.0
days_maximum_number_fruits = 6500.0
potential_fruit_number_at_maturity = 2000
fraction_first_female = 0.3
coeff = XPalm.age_relative_value.(1:length(meteos[1]), days_increase_number_fruits, days_maximum_number_fruits, fraction_first_female, 1.0)
data(DataFrame(months_after_planting=meteos[1].months_after_planting, nfruits=coeff .* potential_fruit_number_at_maturity)) * mapping(:months_after_planting, :nfruits) * visual(Lines) |> draw()
#! it should be around 600 at 50 MAP, then increasing to 1000 at 100MAP (and 2000 at 150MAP) (see PR site in CIGE data)

data(df_female_1) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :TT_since_init, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :biomass, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :biomass_fruits, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :biomass_stalk, color=:Site => nonnumeric) * visual(Scatter) |> draw()

data(df_female_1) * mapping(:timestep, :carbon_demand_non_oil, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :carbon_demand_oil, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :carbon_demand_stalk, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :fruits_number => (x -> x > 0 ? x : 0) => "Number of fruits", color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :carbon_allocation, color=:Site => nonnumeric) * visual(Scatter) |> draw()

df_female_2 = filter(row -> row[:node] == 511, df_female)
data(df_female_2) * mapping(:timestep, :TT_since_init, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_2) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_2) * mapping(:timestep, :biomass, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_2) * mapping(:timestep, :biomass_fruits, color=:Site => nonnumeric) * visual(Scatter) |> draw()


#! Leaf scale
df_leaf = filter(row -> row[:organ] == "Leaf", dfs_all)
select!(df_leaf, findall(x -> any(!ismissing(i) for i in x), eachcol(df_leaf)))

#! control that all leaves have leaf area > 0
@test minimum(df_leaf.leaf_area) >= 0
@test minimum(df_leaf.carbon_demand) >= 0

#! control that the number of leaves at rank > 1 increases each step
df_leaves_rank_sup_1 = combine(groupby(df_leaf, [:Site, :timestep]), :rank => (r -> length(filter(x -> x > 0, r))) => :rank)
data(df_leaves_rank_sup_1) * mapping(:timestep, :rank, color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! control that the number of leaves Opened is steady at mature stage, and is == to rank_leaf_pruning parameter
df_leaves_opened = combine(
    groupby(df_leaf, [:Site, :timestep]),
    :date => unique => :date,
    :months_after_planting => last => :months_after_planting,
    :state => (s -> length(filter(x -> x == "Opened", s))) => :leaves_opened,
    :state => (s -> length(filter(x -> x == "Pruned", s))) => :leaves_pruned,
    :state => (s -> length(filter(x -> x == "undetermined", s))) => :leaves_undetermined,
    :state => (s -> length(filter(x -> x == "Opened" || x == "Pruned", s))) => :leaves_emitted,
    :state => (s -> length(s)) => :leaves_all,
    :pruning_decision => (d -> length(filter(x -> x == "Pruned at rank", d))) => :pruned_at_rank,
    :pruning_decision => (d -> length(filter(x -> x == "Pruned at bunch harvest", d))) => :pruned_at_Harvest,
    :state => (s -> length(s)) => :n_leaves,
    [:state, :leaf_area] => ((s, a) -> sum(a[findall(x -> x == "Opened", s)])) => :leaf_area,
    :biomass => sum => :biomass,
)

CC_leaves = 0.45  # Carbon content of the leaves (gC g-1 dry mass)
df_leaves_year = combine(
    groupby(transform(df_leaves_opened, :date => ByRow(year) => :year), [:Site, :year]),
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass => (x -> minimum(x) * 1e-6 / CC_leaves / params_default[:scene_area] * 10000) => :biomass_ton_ms,
)

data(df_leaves_opened) * mapping(:months_after_planting, :leaves_emitted, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_leaves_opened) * mapping(:months_after_planting, :leaf_area, color=:Site => nonnumeric) * visual(Lines) |> draw()


p_phytomers = data(dfs_plant) * mapping(:timestep, :phytomer_count, color=:Site => nonnumeric) * visual(Lines)
p_leaves_all = data(df_leaves_opened) * mapping(:timestep, :leaves_all, color=:Site => nonnumeric) * visual(Lines)
p_leaves_opened = data(df_leaves_opened) * mapping(:timestep, :leaves_opened, color=:Site => nonnumeric) * visual(Lines)
p_leaves_pruned = data(df_leaves_opened) * mapping(:timestep, :leaves_pruned, color=:Site => nonnumeric) * visual(Lines)
p_leaves_undeter = data(df_leaves_opened) * mapping(:timestep, :leaves_undetermined, color=:Site => nonnumeric) * visual(Lines)
# draw(p_phytomers + p_leaves_all)
draw(p_phytomers + p_leaves_opened + p_leaves_pruned + p_leaves_undeter)

#! Number of leaves undetermined (before opening) should be around 60:
@test maximum(df_leaves_opened.leaves_undetermined) == 64

#! Number of leaves opened + pruned + undetermined should be equal to the number of phytomers emitted:
phytomer_count_per_site = combine(groupby(dfs_plant, :Site), :phytomer_count => last => :phytomer_count)
leaves_emitted_per_site = combine(groupby(df_leaves_opened, :Site), [:leaves_emitted, :leaves_undetermined] => ((x, y) -> last(x) + last(y)) => :phytomer_count)
@test phytomer_count_per_site == leaves_emitted_per_site

#! Number of leaves opened + pruned should be around 100 between 50 and 100MAP:
data(df_leaves_opened) * mapping(:months_after_planting, :leaves_emitted, color=:Site => nonnumeric) * visual(Scatter) |> draw()
leaves_emitted_at_100MAP = filter(row -> row.months_after_planting == 100, df_leaves_opened).leaves_emitted |> mean
leaves_emitted_at_50MAP = filter(row -> row.months_after_planting == 49, df_leaves_opened).leaves_emitted |> mean
# Leaves emmitted is a cumulative value, so we compare with 50 to 100MAP instead:
leaves_emitted_50_to_100MAP = leaves_emitted_at_100MAP - leaves_emitted_at_50MAP # Should be around 100, with ~2 leaves per months emitted

@test leaves_emitted_50_to_100MAP > minimum(nb_leaves_50_to_100MAP_obs) && leaves_emitted_50_to_100MAP < maximum(nb_leaves_50_to_100MAP_obs) # mean ~ 109


data(df_leaves_opened) * mapping(:timestep, :leaves_opened, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :leaves_pruned, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :leaves_undetermined, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :pruned_at_rank, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :pruned_at_Harvest, color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! Control that all leaves that are undetermined are also of rank <1
df_leaves_undetermined = filter(row -> row.state == "undetermined", df_leaf)
@test all(df_leaves_undetermined.rank .< 1)
df_leaves_pruned = filter(row -> row.state == "Pruned", df_leaf)
@test all(df_leaves_pruned.rank .> params_default[:rank_leaf_pruning] .|| df_leaves_pruned.TT_since_init .> params_default[:female][:TT_harvest])

#! controlling leaves biomass (we expect 20 t dry mass ha-1 at 13 years old, see Dufrene et al. 1990 Oléagineux):
data(df_leaves_year) * mapping(:year, :biomass_ton_ms => "Leaf biomass (t[ms] ha⁻¹ year⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()

unique(df_leaves_pruned.node) |> print
df_leaves_pruned_one = filter(x -> x.node == 278 && x.Site == "SMSE", df_leaves_pruned)
minimum(df_leaves_pruned_one.rank) # Pruned at rank 30, very early
df_leaf_278 = filter(x -> x.node == 278 && x.Site == "SMSE", df_leaf)
df_leaf_278.rank[df_leaf_278.rank.<0] .= 0
scatter(df_leaf_278.timestep, df_leaf_278.rank, color=:green, markersize=3)
data(df_leaf_278) * mapping(:timestep, :rank, color=:state) * visual(Scatter) |> draw()
data(df_leaf_278) * mapping(:timestep, :pruning_decision, color=:state) * visual(Scatter) |> draw()
data(df_leaf_278) * mapping(:timestep, :TT_since_init, color=:state) * visual(Scatter) |> draw()
df_leaf_278.final_potential_area

filter(x -> x.state == "Pruned", df_leaf_278).TT_since_init |> minimum
filter(x -> x.state == "undetermined", df_leaf_278).TT_since_init |> maximum


data(df_leaf_278) * mapping(:timestep, :state, color=:state) * visual(Scatter) |> draw()
scatter(df_leaf_278.timestep, df_leaf_278.leaf_area, color=:green, markersize=3)

minimum(df_leaf_TOWE_ts_end_pruned.rank)

df_leaf_TOWE = filter(row -> row.Site == "SMSE", df_leaf)
df_leaf_TOWE_ts_end = filter(row -> row.timestep == 4160, df_leaf_TOWE)
df_leaf_TOWE_ts_end_opened = filter(x -> x.state == "Opened", df_leaf_TOWE_ts_end)
df_leaf_TOWE_ts_end_undetermined = filter(x -> x.state == "undetermined", df_leaf_TOWE_ts_end)
df_leaf_TOWE_ts_end_pruned = filter(x -> x.state == "Pruned", df_leaf_TOWE_ts_end)

data(df_leaf_TOWE) * mapping(:timestep, :final_potential_area => (x -> x * 560.0)) * visual(Scatter) |> draw()

unique(df_leaf.node) |> print
df_leaf_one = filter(row -> row[:node] == 80, df_leaf)
data(df_leaf_one) * mapping(:timestep, :leaf_area, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaf_one) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaf_one) * mapping(:timestep, :pruning_decision, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(filter(row -> row.timestep > 500, df_leaf_one)) * mapping(:timestep, :rank, color=:Site => nonnumeric) * visual(Scatter) |> draw()

data(df_leaf_TOWE) * mapping(:timestep, :pruning_decision, color=:Site => nonnumeric) * visual(Scatter) |> draw()


TT_flowering = 6300.0
duration_fruit_setting = 405.0
TT_druit_number = TT_flowering + duration_fruit_setting
TT_harvest = 12150.0

df_phytomer = filter(row -> row[:organ] == "Phytomer", dfs_all)
scatter(df_phytomer.timestep, df_phytomer.TEff, color=:green, markersize=3)
data(df_phytomer) * mapping(:timestep, :TEff, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_phytomer) * mapping(:timestep, :TT_since_init, color=:Site => nonnumeric) * visual(Scatter) |> draw()

df_phytomer_SMSE = filter(x -> x.Site == "SMSE", df_phytomer)
data(df_phytomer_SMSE) * mapping(:timestep, :TT_since_init, color=:node) * visual(Scatter) |> draw()

filter(row -> row.node == 6, df_phytomer_SMSE) |>
(x -> data(x) * mapping(:timestep, :state, color=:node => nonnumeric) * visual(Lines)) |>
draw()

filter(row -> row.node == 6, df_phytomer_SMSE) |>
(x -> data(x) * mapping(:timestep, :state, color=:node => nonnumeric) * visual(Lines)) |>
draw()

filter(row -> row.node == 386, df_phytomer_SMSE) |>
(x -> data(x) * mapping(:timestep, :state, color=:node => nonnumeric) * visual(Lines)) |>
draw()

df_scene = filter(row -> row[:organ] == "Scene", df)
df_scene.date = meteo.date
df_scene.yearmonth = [Date(Dates.yearmonth(d)...) for d in df_scene.date]
# Computes the index of the month since the beginning of the simulation:
df_scene.months_after_planting = groupindices(groupby(df_scene, :yearmonth))

scatter(df_scene.timestep, df_scene.lai, color=:green, markersize=3)
maximum(df_scene.lai)

scatter(df_scene.lai[365*10:min(365 * 12, length(df_scene.lai))])

df_plant = filter(row -> row[:organ] == "Plant", dfs_all)
df_plant.date = meteo.date
df_plant.yearmonth = [Date(Dates.yearmonth(d)...) for d in df_plant.date]
# Computes the index of the month since the beginning of the simulation:
df_plant.months_after_planting = groupindices(groupby(df_plant, :yearmonth))

scatter(df_plant.timestep, df_plant.leaf_area, color=:green, markersize=3)
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

#! Internodes:
df_internode = filter(row -> row[:organ] == "Internode", dfs_all)
select!(df_internode, findall(x -> any(!ismissing(i) for i in x), eachcol(df_internode)))

# plant scale results for internodes:
df_internodes_plant = combine(
    groupby(df_internode, [:Site, :timestep]),
    :date => unique => :date,
    :months_after_planting => last => :months_after_planting,
    :biomass => sum => :biomass,
    :height => sum => :height,
    :radius => maximum => :radius,
)

CC_internode = 0.45  # Carbon content of the internodes (gC g-1 dry mass)
df_internodes_year = combine(
    groupby(transform(df_internodes_plant, :date => ByRow(year) => :year), [:Site, :year]),
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass => (x -> minimum(x) * 1e-6 / CC_internode / params_default[:scene_area] * 10000) => :biomass_ton_ms,
    :height => minimum => :height,
    :radius => (x -> minimum(x) * 2) => :diameter,
)

#! controlling internodes biomass (we expect 14.68 t dry mass ha-1 at 13 years old, see Dufrene et al. 1990 Oléagineux):
data(df_internodes_year) * mapping(:year, :biomass_ton_ms => "Internodes biomass (t[ms] ha⁻¹ year⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()

#! controlling stem height:
data(df_internodes_year) * mapping(:year, :height => "Stem height (m)", color=:Site => nonnumeric) * visual(Lines) |> draw()

#! controlling stem diameter:
data(df_internodes_year) * mapping(:year, :diameter => "Stem diameter (m)", color=:Site => nonnumeric) * visual(Lines) |> draw()

df_internode_7 = filter(row -> row[:node] == 7 && row.Site == "PR", df_internode)
df_internode_one = filter(row -> row[:node] == 853 && row.Site == "PR", df_internode)

data(df_internode_7) * mapping(:timestep, :potential_height, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_internode_7) * mapping(:timestep, :carbon_demand, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_internode_7) * mapping(:timestep, :Rm, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_internode_7) * mapping(:timestep, :biomass, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_internode_7) * mapping(:timestep, :initiation_age, color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(x -> x.Site == "SMSE", df_internode)) * mapping(:timestep, :initiation_age, color=:node => nonnumeric) * visual(Lines) |> draw()

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