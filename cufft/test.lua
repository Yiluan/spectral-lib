require 'fftw'
require 'cunn'
require 'libcufft'
require 'cucomplex'
dofile('../complex.lua')
cufft = dofile('cufft.lua')




function make_hermitian_weights(nOutputPlanes,nInputPlanes,iH,iW)
    local spatial_weights = torch.zeros(nOutputPlanes,nInputPlanes,iH,iW,2)
    spatial_weights:select(5,1):copy(torch.randn(nOutputPlanes,nInputPlanes,iH,iW))
    local weights = torch.CudaTensor(nOutputPlanes,nInputPlanes,iH,iW,2):zero()
    cufft.fft2d_c2c(spatial_weights:cuda(),weights,1)
    return weights
 end

function test1d()
   nInputLines = 2
   N = 8
   -- real to complex
   x=torch.range(0,nInputLines*N-1):resize(nInputLines,N)
   y=torch.CudaTensor(nInputLines,N/2+1,2)
   x=x:cuda()
   y=y:cuda()
   print('original input:') print(x)
   cufft.fft1d_r2c(x,y)
   print('transform:') print(y)
   x:zero()
   cufft.fft1d_c2r(y,x)
   print('reconstruction:') print(x)

   -- complex to complex
   print('complex to complex')
   x=torch.CudaTensor(nInputLines,N,2):zero()
   y=torch.CudaTensor(nInputLines,N,2):zero()
   x[{{},{},1}]:copy(torch.range(0,nInputLines*N-1))
   print('original input:') print(x)
   cufft.fft1d_c2c(x,y,1)
   print('transform:') print(y)
   x:zero()
   cufft.fft1d_c2c(y,x,-1)
   print('reconstruction:') print(x)
end

function test2d()
   nInputPlanes = 128*96
   N = 32
   M = 32
   -- real to complex
   x = torch.randn(nInputPlanes,N,M):cuda()
   f = torch.CudaTensor(nInputPlanes,N,M/2+1,2)
   r = torch.CudaTensor(nInputPlanes,N,M)
   t = torch.Timer()
   t:reset()
   libcufft.fft2d_r2c(x,f)
   libcufft.fft2d_c2r(f,r)
   r:div(N*M)
   print('time elapse: ' .. t:time().real)
   err = torch.max(torch.abs(x:float()-r:float()))
   print('error=' .. err)
end

function testHermitian()
   local precision = 1e-5
   nSamples = 1
   nInputPlanes = 1
   N = 16
   M = 16
   -- real to complex
   x1 = torch.randn(nSamples,nInputPlanes,N,M):cuda()
   x2 = torch.zeros(nSamples,nInputPlanes,N,M,2):cuda()
   x2:select(5,1):copy(x1)
   f1 = torch.CudaTensor(nSamples,nInputPlanes,N,M/2+1,2)
   f2 = torch.CudaTensor(nSamples,nInputPlanes,N,M,2)
   cufft.fft2d_r2c(x1,f1)
   cufft.fft2d_c2c(x2,f2,1)
   err1 = torch.max(torch.abs(f2[{{},{},{},{1,M/2+1}}]:float()-f1:float()))
   assert(err1 < precision)
   r1 = x1:clone():zero()
   r2 = x2:clone():zero()
   cufft.fft2d_c2r(f1,r1)
   cufft.fft2d_c2c(f2,r2,-1)
   err2 = torch.max(torch.abs(r1:float()-r2:select(5,1):float()))
   assert(err2 < precision)
   f1 = f1:double():squeeze()
   f2 = f2:double():squeeze()
   print('error1=' .. err1)
   print('error2=' .. err2)
end
testHermitian()


function testfft()
   N = 8
   M = 4
   input = torch.randn(N,M)
   input2 = torch.zeros(N,M,2)
   input2:select(3,1):copy(input)
   out1 =cufft.fft2dsingle(input2)
   out2 = cufft.fft2d(input,out2)
end
--testfft()

function test2dc2c()
   nSamples = 1
   nInputPlanes = 1
   N = 8
   M = 8
   x = torch.randn(nSamples,nInputPlanes,N,N):cuda()
   f1 = torch.Tensor(nSamples,nInputPlanes,N,N):cuda()
   f2 = torch.Tensor(nSamples,nInputPlanes,N,N):cuda()
   cufft.fft2d_c2c(x,f1,1,false)
   cufft.fft2d_c2c(x,f2,1,true)
   err = torch.max(torch.abs(f1:float()-f2:float()))
   print('error=' .. err)
end


test2dc2c()

   
--test2d2()




-- test the complex product/accumulation used in fprop, bprop and accGrad
-- WARNING/TODO: this seems to work for powers of 2, but not for certain column 
-- numbers such as 17. Make sure the row/col sizes give the correct answer 
-- before running experiments.   
function test_prod()
   local nMinibatch = math.random(1,10)
   local nInputPlanes = math.random(1,16)
   local nOutputPlanes = math.random(1,16)
   local nRows = 32
   local nCols = 11

   local input = torch.CudaTensor(nMinibatch,nInputPlanes,nRows,nCols,2):normal()
   local weight = torch.CudaTensor(nOutputPlanes, nInputPlanes, nRows, nCols, 2):normal()
   local output = torch.CudaTensor(nMinibatch, nOutputPlanes, nRows,nCols,2):zero()

   print('\nTESTING FPROP')
   local timer = torch.Timer()
   timer:reset()
   cucomplex.prod_fprop(input,weight,output)
   print('CUDA version took ' .. timer:time().real .. ' sec')
   local output2 = torch.CudaTensor(nMinibatch, nOutputPlanes, nRows,nCols,2):zero()
   timer:reset()
   for s=1,nMinibatch do
      for i = 1,nOutputPlanes do
         for j = 1,nInputPlanes do 
			complex.addcmul(input[s][j],weight[i][j],output2[s][i])
         end
      end
   end
   print('Torch version took ' .. timer:time().real .. ' sec')
   output:add(-1,output2)
   print('Norm of difference = ' .. output:norm())
   
   print('\nTESTING BPROP')
   local gradInput = input:zero()
   local gradInput2 = gradInput:clone()
   local gradOutput = output:normal()
   weight:normal()
   cucomplex.prod_bprop(gradOutput,weight,gradInput)
   
   for s = 1,nMinibatch do
      for i = 1,nInputPlanes do
         for j = 1,nOutputPlanes do 
            complex.addcmul(gradOutput[s][j],weight[j][i],gradInput2[s][i])
         end
      end
   end
   gradInput:add(-1,gradInput2)
   print('Norm of difference = ' .. gradInput:norm())
      
   print('\nTESTING ACCGRAD')
   local gradWeight = weight:zero()
   local gradWeight2 = gradWeight:clone()
   gradOutput:normal()
   input:normal()
   cucomplex.prod_accgrad(input, gradOutput, gradWeight)
   for j = 1,nOutputPlanes do 
      for i = 1,nInputPlanes do
         for s = 1,nMinibatch do
            complex.addcmul(gradOutput[s][j],input[s][i],gradWeight2[j][i])
         end
      end
   end
   gradWeight:add(-1,gradWeight2)
   print('Norm of difference = ' .. gradWeight:norm())
end

test_prod()
