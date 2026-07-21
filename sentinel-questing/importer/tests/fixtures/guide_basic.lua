RXPGuides.RegisterGuide([[
#version 7
#group RestedXP Test Guide (A)
<< Alliance
#name 1-5 Test Zone
#defaultfor Human

step << !Human
    +You have selected a guide meant for Humans.
step
    .accept 1598 >> Accept The Stolen Tome
    .target Dane Winslow
    #label TOME
step << Warlock
    #completewith TOME
    .turnin 1598 >> Turn in The Stolen Tome
    .goto Elwynn Forest,48.2,42.9
]])
