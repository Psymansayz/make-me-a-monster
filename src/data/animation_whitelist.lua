-- The only animations the plugin lists: chat and head animations that work on a chat head. Read by
-- src/game/listed_animations.lua, which looks up just these ids (the animation configs are not scanned).
return {
    -- The same animation as one in the animations listed (src/data/animations.lua) (a longer take, a loop...), or one kept out of the dropdown for now: never listed, so kept apart.
    duplicates = {
        9743, 9744, 9745, 9747, 9748, 9749, 9751, 9752, 9753, 9758, 9759, 9760,
        9762, 9763, 9764, 9766, 9767, 9768, 9770, 9771, 9772, 9774, 9775, 9776,
        9778, 9779, 9780, 9782, 9783, 9784, 9786, 9787, 9788, 9790, 9791, 9792,
        9806, 9808, 9809, 9810, 9812, 9813, 9814, 9828, 9829, 9830, 9832, 9833,
        9834, 9837, 9838, 9839, 9844, 9845, 9846, 9848, 9849, 9850, 9852, 9853,
        9854, 14701, 14702, 14704, 14705, 14706, 14707, 14708, 14709, 14710, 14711, 17297,
        29829, 29830, 29831, 29833, 29834, 29835, 29837, 29838, 29839, 35413, 35414, 35415,
        35416, 35417,
    },
}
