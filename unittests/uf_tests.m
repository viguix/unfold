function uf_tests()
%This function runs the main dc-functions with a lot of parameter pairings
%(~10.000) and tests whether errors occur
% It also runs the tests in this folder 
% It also checks how large the difference between estimated signal and
% original signal is and throws an error if the difference is too large

%separate tests
test_addmarginals
test_continuousArtifact
test_designmat
test_glmfit
test_imputeMissing
test_splines
test_timeexpandDesignmat





% Multi-Test
cfg = struct();
cfg.designmat.coding = {'effects','reference'};
cfg.designmat.splinespacing = {'linear','quantile'};
cfg.timeexpandDesignmat.timelimits = {[-0.5,1.5],[-0.5,-0.1],[1 2]};
cfg.timeexpandDesignmat.method = {'stick','splines','fourier'};
cfg.timeexpandDesignmat.timeexpandparam = [4, 16, 35];
cfg.timeexpandDesignmat.sparse = [0,1];
cfg.glmfit.method={'lsmr','matlab','pinv'};
cfg.glmfit.channel = 1;
% cfg.beta2EEG.convertSplines = [0,1]; % deprecated with the new spline
% implementation
cfg.beta2EEG.unfold = [-1,0,1];
cfg.beta2EEG.channel = 1;

    function Y = allcomb_wrapper(varargin)
        tmp = [];
        for k= 1:length(varargin)
            A = varargin{k};
            if isstruct(A)
                A = struct2cell(A);
            end
            for l = 1:length(A)
                if all(isnumeric(A{l}))
                    A{l} = num2cell(A{l});
                end
            end
            tmp = [tmp; A];
        end
        Y = allcomb(tmp{:});
        Y = Y(randperm(size(Y,1)),:);
    end

designmat = allcomb_wrapper(cfg.designmat);
timeexpand = allcomb_wrapper(cfg.timeexpandDesignmat);
glmfit = allcomb_wrapper(cfg.glmfit);
beta2EEG = allcomb_wrapper(cfg.beta2EEG);
% error


% The function has to be defined before the test-case loop due to matlab
% constraints in inline-function placement.
    function do_the_testing(testCase,EEG,cfgDesign)
        testCase
        for d = designmat'
            d
            cfgDesignLoop = cfgDesign;
            cfgDesignLoop.coding = d{1};
            cfgDesignLoop.splinespacing = d{2};
            EEGd = uf_designmat(EEG,cfgDesignLoop);
            
            for t = timeexpand'
                t
                EEGt = uf_timeexpandDesignmat(EEGd,'timelimits',t{1},'method',t{2},'timeexpandparam',t{3},'sparse',t{4});
                
                for g = glmfit'
                    g
                    EEGg= uf_glmfit(EEGt,'method',g{1},'channel',g{2});
                    assert(~any(isnan(EEGg.unfold.beta_dc(:))),'error, found nan after fit');
                    for b = beta2EEG'
                        b   
                        

                        EEGb = EEGg;
                        if b{1} == 0
                            EEGb = uf_epoch(EEGb,'timelimits',t{1});
                            EEGb = uf_glmfit_nodc(EEGb);
                        end
                        ufresult = uf_condense(EEGb,'deconv',b{1},'channel',b{2});
                        if strcmp(t{2},'stick') && testCase==14 && b{2} == 1 && all(t{1} == [-0.5,1.5])
                            if ~isfield(EEGb,'urevent') || isempty(EEG.urevent)
                                EEGb.urevent = EEG.event; % this field is populated in uf_epoch
                            end
                            multWith = ones(1,size(EEGb.unfold.X,2));
                            for col = 1:size(EEGb.unfold.X,2)
                                ix = ismember({EEGb.urevent.type},EEGb.unfold.eventtypes{EEGb.unfold.cols2eventtypes(col)});
                                multWith(col) = mean(EEGb.unfold.X(ix,col),1);
                            end
                            beta = bsxfun(@times,squeeze(ufresult.beta),multWith);
                            orgSig = [zeros(5,5),EEGb.sim.separateSignal,zeros(5,5)];
                            resid = abs(beta - orgSig');
                            % normalize
                            resid = bsxfun(@rdivide,resid',mean(orgSig,2));
                            if mean(resid(:)) > 0.01
                                error('a big difference between original signal and estimated signal has been detected')
                            end
                                
                        end
                    end
                end
            end
        end
    end

for testCase = [15 8 1]
    tic
    EEG = simulate_test_case(testCase,'noise',0,'basis','box');
    cfgDesign = [];
    cfgDesign.eventtypes = {'stimulusA'};
    cfgDesign.coding = 'dummy';
    switch testCase
        case {1,2}
            cfgDesign.formula = 'y ~ 1';
        case {3,4}
            cfgDesign.formula = 'y ~ 1+ conditionA';
            cfgDesign.categorical = {'conditionA'};
        case {5,6}
            cfgDesign.formula = 'y ~ 1+ continuousA';
        case {7,8}
            cfgDesign.formula = 'y ~ 1 + spl(splineA,10)';
            
        case {9,10}
            cfgDesign.formula = {'y~1','y~1'};
            cfgDesign.eventtypes = {'stimulusA','stimulusB'};
        case {11,12}
            cfgDesign.formula = {'y~1','y~1','y~1'};
            cfgDesign.eventtypes = {'stimulusA','stimulusB','stimulusC'};
        case {13,14}
            cfgDesign.formula = {'y~1','y~1+conditionA','y~1+continuousA'};
            cfgDesign.eventtypes = {'stimulusA','stimulusB','stimulusC'};
            cfgDesign.categorical = {'conditionA'};
        case 15
            cfgDesign.formula   = {'y~1',       'y~1+cat(conditionA)*continuousA', 'y~1+spl(splineA,5)+spl(splineB,5)+continuousA'};
            cfgDesign.eventtypes = {'stimulus1', 'stimulus2',                       'stimulus3'};
    end
    
    
    do_the_testing(testCase,EEG,cfgDesign)
%     evalc('do_the_testing(testCase,EEG,cfgDesign)')
    
    fprintf('%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\n %.2fs \n %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% \n',toc)
    
end

%     timelimits = [-0.5,1.5];

%     %%
%     % EEG = uf_epoch(EEG,'timelimits',timelimits);
%     % EEG = uf_glmfit_nodc(EEG); %does not overwrite
%
%     %%
%
%     % ufresult_epoch = uf_beta2EEG(EEG,'unfold',0);
%
%     multWith = ones(1,size(EEG.unfold.X,2));
%     for col = 1:size(EEG.unfold.X,2)
%         ix = ismember({EEG.urevent.type},EEG.unfold.eventtypes{EEG.unfold.cols2eventtypes(col)});
%         multWith(col) = mean(EEG.unfold.X(ix,col),1);
%     end
%     ufresult.beta*multWith;
% end

end
