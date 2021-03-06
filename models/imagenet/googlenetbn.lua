-- Batch normalized googlenet

require 'nn'
require 'cunn'
require 'cudnn'
local function inception(input_size, config)
   local concat = nn.Concat(2)
   if config[1][1] ~= 0 then
      local conv1 = nn.Sequential()
      conv1:add(cudnn.SpatialConvolution(input_size, config[1][1],1,1,1,1)):add(cudnn.ReLU(true))
      conv1:add(cudnn.SpatialBatchNormalization(config[1][1],1e-3))
      conv1:add(cudnn.ReLU(true))
      concat:add(conv1)
   end

   local conv3 = nn.Sequential()
   conv3:add(cudnn.SpatialConvolution(  input_size, config[2][1],1,1,1,1)):add(cudnn.ReLU(true))
   conv3:add(cudnn.SpatialBatchNormalization(config[2][1],1e-3))
   conv3:add(cudnn.ReLU(true))
   conv3:add(cudnn.SpatialConvolution(config[2][1], config[2][2],3,3,1,1,1,1)):add(cudnn.ReLU(true))
   conv3:add(cudnn.SpatialBatchNormalization(config[2][2],1e-3))
   conv3:add(cudnn.ReLU(true))
   concat:add(conv3)

   local conv3xx = nn.Sequential()
   conv3xx:add(cudnn.SpatialConvolution(  input_size, config[3][1],1,1,1,1)):add(cudnn.ReLU(true))
   conv3xx:add(cudnn.SpatialBatchNormalization(config[3][1],1e-3))
   conv3xx:add(cudnn.ReLU(true))
   conv3xx:add(cudnn.SpatialConvolution(config[3][1], config[3][2],3,3,1,1,1,1)):add(cudnn.ReLU(true))
   conv3xx:add(cudnn.SpatialBatchNormalization(config[3][2],1e-3))
   conv3xx:add(cudnn.ReLU(true))
   conv3xx:add(cudnn.SpatialConvolution(config[3][2], config[3][2],3,3,1,1,1,1)):add(cudnn.ReLU(true))
   conv3xx:add(cudnn.SpatialBatchNormalization(config[3][2],1e-3))
   conv3xx:add(cudnn.ReLU(true))
   concat:add(conv3xx)

   local pool = nn.Sequential()
   --pool:add(cudnn.SpatialZeroPadding(1,1,1,1)) -- remove after getting nn R2 into fbcode
   if config[4][1] == 'max' then
      pool:add(cudnn.SpatialMaxPooling(3,3,1,1,1,1):ceil())
   elseif config[4][1] == 'avg' then
      pool:add(cudnn.SpatialAveragePooling(3,3,1,1,1,1):ceil())
   else
      error('Unknown pooling')
   end
   if config[4][2] ~= 0 then
      pool:add(cudnn.SpatialConvolution(input_size, config[4][2],1,1,1,1)):add(cudnn.ReLU(true))
      pool:add(cudnn.SpatialBatchNormalization(config[4][2],1e-3))
      pool:add(cudnn.ReLU(true))
   end
   concat:add(pool)

   return concat
end

function createModel(opt)
   local features = nn.Sequential()
   features:add(cudnn.SpatialConvolution(3,64,7,7,2,2,3,3))
   features:add(cudnn.SpatialBatchNormalization(64,1e-3))
   features:add(cudnn.ReLU(true))
   features:add(cudnn.SpatialMaxPooling(3,3,2,2):ceil())
   features:add(cudnn.SpatialConvolution(64,64,1,1))
   features:add(cudnn.SpatialBatchNormalization(64,1e-3))
    features:add(cudnn.ReLU(true))
   features:add(cudnn.SpatialConvolution(64,192,3,3,1,1,1,1))
   features:add(cudnn.SpatialBatchNormalization(192,1e-3))
   features:add(cudnn.ReLU(true))
   features:add(cudnn.SpatialMaxPooling(3,3,2,2):ceil())


--   features:add(cudnn.SpatialConvolution(3,64,3,3,1,1,0,0))
 --  features:add(cudnn.SpatialBatchNormalization(64,1e-3))
 --  features:add(cudnn.ReLU(true))
 --  features:add(cudnn.SpatialConvolution(64,192,3,3,1,1,0,0))
 --  features:add(cudnn.SpatialBatchNormalization(192,1e-3))
 --  features:add(cudnn.ReLU(true))
--   features:add(cudnn.SpatialMaxPooling(3,3,2,2):ceil())
   features:add(inception( 192, {{ 64},{ 64, 64},{ 64, 96},{'avg', 32}})) -- 3(a)
   features:add(inception( 256, {{ 64},{ 64, 96},{ 64, 96},{'avg', 64}})) -- 3(b)
   features:add(inception( 320, {{  0},{128,160},{ 64, 96},{'max',  0}})) -- 3(c)
   features:add(cudnn.SpatialConvolution(576,576,2,2,2,2))
   features:add(cudnn.SpatialBatchNormalization(576,1e-3))
   features:add(cudnn.ReLU(true))
   features:add(inception( 576, {{224},{ 64, 96},{ 96,128},{'avg',128}})) -- 4(a)
   features:add(inception( 576, {{192},{ 96,128},{ 96,128},{'avg',128}})) -- 4(b)
   features:add(inception( 576, {{160},{128,160},{128,160},{'avg', 96}})) -- 4(c)
   features:add(inception( 576, {{ 96},{128,192},{160,192},{'avg', 96}})) -- 4(d)

   local main_branch = nn.Sequential()
   main_branch:add(inception( 576, {{  0},{128,192},{192,256},{'max',  0}})) -- 4(e)
   main_branch:add(cudnn.SpatialConvolution(1024,1024,2,2,2,2))
   main_branch:add(cudnn.SpatialBatchNormalization(1024,1e-3))
   main_branch:add(cudnn.ReLU(true))
   main_branch:add(inception(1024, {{352},{192,320},{160,224},{'avg',128}})) -- 5(a)
   main_branch:add(inception(1024, {{352},{192,320},{192,224},{'max',128}})) -- 5(b)
   main_branch:add(cudnn.SpatialAveragePooling(7,7,1,1))
   main_branch:add(nn.View(1024):setNumInputDims(3))
   main_branch:add(nn.Linear(1024,1000))
   main_branch:add(nn.LogSoftMax())

   -- add auxillary classifier here (thanks to Christian Szegedy for the details)
--   local aux_classifier = nn.Sequential()
--   aux_classifier:add(cudnn.SpatialAveragePooling(5,5,3,3):ceil())
--   aux_classifier:add(cudnn.SpatialConvolution(576,128,1,1,1,1))
--   aux_classifier:add(cudnn.SpatialBatchNormalization(128,1e-3))
--   aux_classifier:add(cudnn.ReLU(true))
--   aux_classifier:add(nn.View(128*4*4):setNumInputDims(3))
--   aux_classifier:add(nn.Linear(128*4*4,768))
--   aux_classifier:add(cudnn.ReLU())
--   aux_classifier:add(nn.Linear(768,opt.num_classes))
--   aux_classifier:add(nn.LogSoftMax())

--   local splitter = nn.Concat(2)
--   splitter:add(main_branch):add(aux_classifier)
   local model = nn.Sequential():add(features):add(main_branch)

   model:cuda()
   --model = makeDataParallel(model, nGPU) -- defined in util.lua
   model.imageSize = 256
   model.imageCrop = 224


   return model
end

return createModel
