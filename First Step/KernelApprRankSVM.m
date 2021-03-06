classdef KernelApprRankSVM

properties
    C;
    kernel;
    gamma;
    coef0;
    degree;
    seed;
    appr_type;
    kernelsampler;
    n_components;
    OutputWeight;
    TrainTime;
    TrainMAP;
    TrainNDCG;
    metric_type;
end

methods

    function obj = KernelApprRankSVM(n_components, C, appr_type, kernel, gamma, coef0, degree, seed)
        obj.n_components = n_components;
        obj.C = C;
        obj.appr_type = appr_type;
        obj.kernel = kernel;
        obj.gamma = gamma;
        obj.coef0 = coef0;
        obj.degree = degree;
        obj.seed = seed;
    end

    function obj = fit(obj, X_train, Y_train, Q_train, option)
        %% input option
        obj.metric_type = option.metric_type;
        if isfield(option, 'seed')
            obj.seed = option.seed;
        else
            obj.seed = fix(mod(cputime,100));
        end

        t1=tic;

        A = generate_constraints(Y_train, Q_train);


        switch lower(obj.appr_type)
            case 'fourier'
                n_features = size(X_train,2);
                obj.kernelsampler = RBFSampler(obj.n_components, n_features, obj.gamma, obj.seed);
            case 'nystroem'
                obj.kernelsampler = NystroemSampler(obj.n_components, obj.kernel, ...
                    obj.gamma, obj.coef0, obj.degree, obj.seed);
                obj.kernelsampler = fit(obj.kernelsampler, X_train);
            case 'improvednystroem'
                obj.kernelsampler = ImprovedNystroemSampler(obj.n_components, obj.kernel, ...
                    obj.gamma, obj.coef0, obj.degree, obj.seed);
                obj.kernelsampler = fit(obj.kernelsampler, X_train);
            otherwise
                warning('error');
        end

        H = transform(obj.kernelsampler, X_train);
        obj.n_components = size(H,2);

        opt.lin_cg=1;
        opt.verbose=option.verbose;
        if isfield(option,'iter_max_Newton')
           opt.iter_max_Newton = option.iter_max_Newton;
        end;  
        obj.OutputWeight = ranksvm(H, A, obj.C*ones(size(A,1),1), zeros(size(H,2),1),opt);

        obj.TrainTime = toc(t1);

        % TrainingTime=toc;
        %%%%%%%%%%% Calculate the training accuracy
        pred=(H * obj.OutputWeight);

        obj.TrainMAP  = compute_map(pred, Y_train, Q_train);
        obj.TrainNDCG = compute_ndcg(pred, Y_train, Q_train, obj.metric_type.k_ndcg);
    end

    function [pred, TestTime] = predict(obj, X)
        t1=clock;
        H_test = transform(obj.kernelsampler, X);
        pred=(H_test * obj.OutputWeight);
        t2 = clock;
        TestTime = etime(t2,t1);
    end

end
end

function A = generate_constraints(Y, qids)
  nq = length(qids);
  
  I=zeros(1e7,1); J=I; V=I; nt = 0;
  
  ind = 0;
  for i=1:nq
    qs = qids{i};
    ind = ind(end)+[1:length(qs)]';
    Y2 = Y(qs);
    n = length(ind);
    [I1,I2] = find(repmat(Y2,1,n)>repmat(Y2',n,1));
    n = length(I1);
    I(2*nt+1:2*nt+2*n) = nt+[1:n 1:n]'; 
    J(2*nt+1:2*nt+2*n) = [ind(I1); ind(I2)];
    V(2*nt+1:2*nt+2*n) = [ones(n,1); -ones(n,1)];
    nt = nt+n;
  end;
  A = sparse(I(1:2*nt),J(1:2*nt),V(1:2*nt));    
  if size(A,2)~=size(Y,1)
      A(size(A,1),size(Y,1))=0;
  end
end
