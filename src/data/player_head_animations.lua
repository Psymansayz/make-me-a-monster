-- Animations for the player's own head. The animations the plugin lists are for NPC heads (HUMAN_UPDATE_CHATHEAD_...);
-- the player's head plays the matching HUMAN_ACTOR_CHATHEAD_... ones. Read by src/game/head_swap.lua.
return {
    -- A listed animation's id = the id of its player twin (the same emotion and strength; names in
    -- player_head_animations_names.lua). One with no twin (a non-human animation) is played as it is.
    twin = {
        [9742] = 37920,
        [9746] = 37921,
        [9750] = 37922,
        [9757] = 37910,
        [9761] = 37911,
        [9765] = 37912,
        [9769] = 37926,
        [9773] = 37927,
        [9777] = 37928,
        [9781] = 37907,
        [9785] = 37908,
        [9789] = 37909,
        [9793] = 37932,
        [9802] = 37936,
        [9803] = 37902,
        [9804] = 37903,
        [9807] = 37902,
        [9811] = 37933,
        [9827] = 37930,
        [9831] = 37929,
        [9835] = 37916,
        [9836] = 37931,
        [9840] = 37915,
        [9841] = 37914,
        [9842] = 37913,
        [9843] = 37904,
        [9847] = 37905,
        [9851] = 37906,
        [11009] = 37935,
        [12648] = 37917,
        [12649] = 37918,
        [12650] = 37919,
        [29828] = 37923,
        [29832] = 37924,
        [29836] = 37925,
    },
    -- Player animations that also stand for a listed animation (when switching back to an NPC's head), though
    -- another player animation is its twin: { [player animation] = listed animation }. MIND_READ for the eyeglo mind
    -- meld, whose twin is GNOME_MIND_MELD.
    alsoFor = { [37934] = 11009 },
    -- Played on the player's own head when none is chosen, where a head is shown outside dialogue (the variants
    -- window): HUMAN_ACTOR_CHATHEAD_NEUTRAL_STANDARD.
    neutral = 37902,
    -- Where an NPC animation has no player twin, the one used when switching to the player's own head:
    -- HUMAN_ACTOR_CHATHEAD_EVIL_LAUGH_STANDARD.
    fallback = 37913,
    -- The same for an NPC head: HUMAN_UPDATE_CHATHEAD_EVIL_LAUGH_LEN_ALL.
    npcFallback = 9842,
}
