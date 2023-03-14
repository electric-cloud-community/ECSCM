// The delete DevOpsInsight Datasource script is a no-op for ElectricFlow CI schedules. 
// We do not delete the CI schedules from here. CI schedules are managed from platform 
// pages. The deleteDevOpsInsightDataSource API will take care of breaking the association
// to this CI schedule. 


return true