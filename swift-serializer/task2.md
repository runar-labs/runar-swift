Continue the implementation of @swift-serializer and swift-serializer-macros

The document /Users/rafael/dev/runar-swift/swift-serializer/CURRENT_STATE_AND_PLAN.md provide a detailed plan what needs to be done and what is alradu properly done.


DO NOT CHANGE ANYTHING THAT IS NOT IDENTIFIED IN TEH PLAN AS SOMETHING WE NEED TO IMPLEMENT OR CHAGNE
SPECIALT THE FETURE ALREADY DONE AND PROPERLTY IMPLEMENTED>> DO NOT DESTROY THEM

IF YOU NEED TO TOUCH ANY OF THEM, stop and provide complete context and reason, so I can review and approave the change, otherwise DO NOT CHANGE ANY OF THE FEAUREDS ALREADY PROPERLY IMPLEMENTED - check CURRENT_STATE_AND_PLAN.md to know these features/files/types

Implement all the missign features, accordinly to the plan and always double check with the rust code. The goal is for the swfit featurets to be 100% aligned to the rust implementaiotn. nothing more, nothing less.

/Users/rafael/dev/runar-swift/swift-serializer/LabelResolverDesign.md provide details specs fo rhe label resover features. follow it 100% -  the LabelResolverFactory and Cache SHUOLD NOT BE IMPLEMENTED NOW>. this is for future reference when doing the main node.

al the tests must also mimic?follow the RUST tests. we need to test all tehs me scenarion that rust tests does /Users/rafael/dev/runar-swift/runar-rust/runar-serializer/tests KEEP MACRO tests in the macros packge.. and serialier test in the serializer package. (that migh differ from rusts organization)

GO STEP by step/feature by features and when u implement one feauture write the tests for it.(ALWAYS COMPLET TESTS, no mocks, no stubs.. no shortcuts or hacks.) follow our rules always /Users/rafael/dev/runar-swift/.cursor/rules/code-standards.mdc