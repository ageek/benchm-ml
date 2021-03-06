library(readr)
library(ROCR)
library(xgboost)
library(parallel)
library(Matrix)

set.seed(123)

d_train <- read_csv("train-10m.csv")
d_valid <- read_csv("valid.csv")
d_test <- read_csv("test.csv")

for (k in c("Month","DayofMonth","DayOfWeek","UniqueCarrier","Origin","Dest","dep_delayed_15min")) {
  d_train[[k]] <- as.factor(d_train[[k]])
  d_valid[[k]] <- as.factor(d_valid[[k]])
  d_test[[k]] <- as.factor(d_test[[k]])
}

system.time({
  X_train_valid_test <- sparse.model.matrix(dep_delayed_15min ~ .-1, data = rbind(d_train, d_valid, d_test))
  n1 <- nrow(d_train)
  n2 <- nrow(d_valid)
  n3 <- nrow(d_test)
  X_train <- X_train_valid_test[1:n1,]
  X_valid <- X_train_valid_test[(n1+1):(n1+n2),]
  X_test <- X_train_valid_test[(n1+n2+1):(n1+n2+n3),]
})
dim(X_train)

dxgb_train <- xgb.DMatrix(data = X_train, label = ifelse(d_train$dep_delayed_15min=='Y',1,0))
dxgb_valid <- xgb.DMatrix(data = X_valid, label = ifelse(d_valid$dep_delayed_15min=='Y',1,0))
dxgb_test  <- xgb.DMatrix(data = X_test,  label = ifelse(d_test$dep_delayed_15min =='Y',1,0))



params <- expand.grid(max_depth = c(2,5,10,20,50), eta = 0.01, 
      min_child_weight = 1, subsample = 0.5)

for (k in 1:nrow(params)) {
  prm <- params[k,]
  print(prm)
  print(system.time({
    n_proc <- detectCores()
    md <- xgb.train(data = dxgb_train, nthread = n_proc, 
                 objective = "binary:logistic", nround = 10000, 
                 max_depth = prm$max_depth, eta = prm$eta, 
                 min_child_weight = prm$min_child_weight, subsample = prm$subsample, 
                 watchlist = list(valid = dxgb_valid, train = dxgb_train), eval_metric = "auc",
                 early_stop_round = 100, printEveryN = 100)
  }))
  phat <- predict(md, newdata = X_test)
  rocr_pred <- prediction(phat, d_test$dep_delayed_15min)
  print(performance(rocr_pred, "auc"))
}



