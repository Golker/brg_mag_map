% This script is a modified copy of the original Mapping_Baseline script
% used for the MagPIE IPIN paper; it computes the map of the norm of the
% magnetometer measurements from training data
%   Originally written by: David Hanley
%   Modifications by: Alex Faustino

clear
close all

%% Load Data

initOptions.env = input('Select mapping environment. (C)SL first floor, (L)oomis Lab first floor, or (T)albot Lab third floor: ','s');
initOptions.plat = input('Select platform. (U)GV or (S)marthphone: ','s');
initOptions.meas = input('Select type of magnetometer measurement. (N)orm, (x) component, (y) component, or (z) component: ','s');

[x, y, xTrainFull, yTrainFull] = LoadData(initOptions);
                        
% % Absolute path to platform data directory
% addpath('Z:\Desktop\BRG\MagPIE\Data Set\Loomis First Floor\UGV')
% % addpath('\\ad.uillinois.edu\engr\instructional\afausti2\Desktop\BRG\MagPIE\Data Set\Talbot Third Floor\UGV')
% load('GT_Mag.mat'), load('x.mat'), load('y.mat'), load('xTrain.mat')
% load('yTrain.mat'), load('xDevel.mat'), load('yDevel.mat'), load('xTest.mat')
% load('yTest.mat')

% Absolute path for GPML matlab directory
% addpath('Z:\Desktop\BRG\GP for Machine Learning\gpml-matlab\gpml-matlab-v4.0-2016-10-19')
addpath('\\ad.uillinois.edu\engr\instructional\afausti2\Desktop\BRG\GP for Machine Learning\gpml-matlab\gpml-matlab-v4.0-2016-10-19')

% Startup GPML
startup
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Cross validation sets

numCVSets = numel(xTrainFull);

for l=1:numCVSets
    xDevel = xTrainFull{1,l};
    yDevel = yTrainFull{1,l};
    
    firstTrainSet = true;
    for m=1:numCVSets
        if (m~=l)
            if (firstTrainSet)
                xTrain = xTrainFull{1,m};
                yTrain = yTrainFull{1,m};
                firstTrainSet = false;
            else
                xTrain = [xTrain; xTrainFull{1,m}];
                yTrain = [yTrain; yTrainFull{1,m}];
            end
        end
    end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Set Covariance Function and Initialize Hyperparameters

% Use targets to determine initial hyperparameter values
mu_y = sum(y)/length(y);
sig_y = std(y);

y_stats = sprintf('Mean of targets (y): %.4f\nStandard deviation of targets: %.4f',mu_y,sig_y);
disp(y_stats)

% Setup priors
pd = {@priorDelta};     % Fixes hyperparameter
pg = {@priorGauss, mu_y, sig_y^2};      % Gaussian prior

% Mean function
% mean = {@meanSum,{@meanConst, @meanLinear}};
% hyp.mean = [mu_y; 1; 1; 1];
% prior.mean = {pg, [], [], []};      % Gaussian prior on offset, none for linear
mean = {@meanConst};
hyp.mean = mu_y;
prior.mean = {pg};
% 
% Covariance function
% cov = {{@covSEiso},{@covSEiso}};    % Squared exponential covariance function
cov = {{@covSEard},{@covSEard}};    % SE with auto relevance detection (ARD)
% cov = {{@covMaternard, 3},{@covMaternard, 3}};       % Matern kernel with ARD

% Likelihood function
lik = {@likGauss};        % Gaussian Likelihood Function

% Hyperparameters for cov and lik depending on target type
switch initOptions.meas
    case {'N','n'}
        hyp.lik = log(0.495);   % Log of noise std deviation (sigma n)
        hyp.cov = log([1e-4; 1; 1e-4; 0.495]);
    case {'X','x'}
        hyp.lik = log(0.4217);
        hyp.cov = log([1e-4; 1; 1e-4; 0.4217]);
    case {'Y','y'}
        hyp.lik = log(0.5206);
        hyp.cov = log([1e-4; 1; 1e-4; 0.5206]);
    case {'Z','z'}
        hyp.lik = log(0.3320);
        hyp.cov = log([1e-4; 1; 1e-4; 0.3320]);
end
% prior.cov = {pd,pd,pd,[]};  % Fix characteristic length scale
% prior.lik = {pd};    % Fix noise std deviation hyperparameter
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Sparse approximation for the full GP of the training set

equalSourcePointError = true;
while(equalSourcePointError)
    try
        % Subset of Regressors
        nu = floor(7e-4*length(x(:,1)));   % Number of inducing points
%         nu = 150;
        iu = randperm(length(xTrain(:,1)));
        iu = iu(1:nu);
        u = x(iu,:);
        % hyp.xu = u; % Optimize inducing inputs jointly with hyperparamters
        xg = {u(:,1), u(:,2)};    % Plain Kronecker structure

        errmsg = CheckEqSourcePt(x, xg);
        
        if isempty(errmsg)
            equalSourcePointError = false;
        else
            error(errmsg)
        end
    catch ME
        disp('Equal source point error. Attempting new subset...')
    end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Optimize Hyperparameters 

% Kernel approximation
% covfuncF = {'apxSparse',cov,u};
covg = {'apxGrid',cov,xg};
opt.cg_maxit = 500;
opt.cg_tol = 1e-5;
opt.stat = true;                   % show some more information during inference
opt.ndcovs = 25;                    % ask for sampling-based (exact) derivatives

% Inference shortcut
% 0.0 -> VFE, 1.0 -> FITC
% inf = @(varargin) infGaussLik(varargin{:}, struct('s', 1.0));
inf = @(varargin) infGrid(varargin{:}, opt);
infP = {@infPrior,inf,prior};
        
% Construct a grid covering the training data
xg = apxGrid('create',xTrain(:,1:2),true,[nu nu]);
    
% Compute hyperparameters by minimizing negative log marginal likelihood
% w.r.t. hyperparameters
tic 
disp('Optimizing hyperparameters...')
hyp = minimize(hyp, @gp, -100, infP, mean, covg, lik, xTrain(:,1:2), yTrain);

% Print results to console
sig_n = sprintf('Inferred noise standard deviation is: %.4f', exp(hyp.lik));
disp(sig_n)
mu_inf = sprintf('Inferred Mean is: %.4f', hyp.mean);
disp(mu_inf)
l_inf = sprintf('Inferred characteristic length scale is: %.4e', exp(hyp.cov(1)));
disp(l_inf)
sig_inf = sprintf('Inferred signal standard deviation is: %.4f', exp(hyp.cov(4)));
disp(sig_inf)
nlml = gp(hyp, infP, mean, covg, lik, xTrain(:,1:2), yTrain);
nlml_x = sprintf('Negative log probability of training data: %.6e', nlml);
disp(nlml_x)
toc
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Predict values for test data

% Construct grid of test data
[xs,ns] = apxGrid('expand',xDevel(:,1:2));

% Run inference
disp('Running inference...')
tic 
[post,nlZ,dnlZ] = infGrid(hyp, mean, covg, lik, xTrain(:,1:2), yTrain, opt);
toc

tic
disp('Predicting mean and variance for test data...')
[fmu,fs2,ymu,ys2] = post.predict(xs);
% [m, s2] = gp(hyp, infP, mean, covg, lik, xTrain, yTrain, xDevel);
% [m, s2] = gp(hyp, inf, mean, covfuncF, lik, xTrain, yTrain, xTest);
toc

ys = ys2.^(1/2);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Determine Mahalanobis Distance Between Predictions and Full Data

develMD = mahal([xDevel ymu],[x y]);
MD.max = max(develMD);
MD.min = min(develMD);
MD.mean = sum(develMD)/length(develMD);
MD.med = median(develMD);

% testMD = mahal([xTest m],[x y]);
% MD.max = max(testMD);
% MD.min = min(testMD);
% MD.mean = sum(testMD)/length(testMD);
% MD.med = median(testMD);

disp(MD)

% Qualitatively evalute of predictions by plotting MD against expected Chi
% square distribution
chi2pd = makedist('Gamma','b',2);   % Chi^2 special case of Gamma
qqplot(develMD,chi2pd)
% qqplot(testMD,chi2pd)

% Relative error between prediction and observation

diffPredict = abs((yDevel - ymu)./yDevel);
diff.max = max(diffPredict);
diff.min = min(diffPredict);
diff.mean = sum(diffPredict)/length(diffPredict);
diff.med = median(diffPredict);

disp(diff)

%% Plot

% Predicted mean with +/- 1 std deviation
figure(2)
plot3(x(:,1),x(:,2),y,'.')
hold on;
scatter3(xDevel(:,1),xDevel(:,2),ymu)
hold on;
% scatter3(xDevel(:,1),xDevel(:,2),s2)
scatter3(xDevel(:,1),xDevel(:,2),ymu-2*ys)
hold on;
scatter3(xDevel(:,1),xDevel(:,2),ymu+2*ys)

% Difference between predictions and observations
figure(3)
scatter3(xDevel(:,1),xDevel(:,2),diffPredict)

% End CV loop
end