var Lotto = artifacts.require("./Lotto.sol");
var ProfitSplitter = artifacts.require("./ProfitSplitter.sol");
var Raffle = artifacts.require("./Raffle.sol");

module.exports = function(deployer) {
  var profitSplitterAddress;
  var lottoAddress;
  var raffleAddress;

  deployer.deploy(ProfitSplitter).then(function() {
    profitSplitterAddress = ProfitSplitter.address;
    return deployer.deploy(Lotto);
  }).then(function() {
    lottoAddress = Lotto.address;
    return deployer.deploy(Raffle, lottoAddress);
  }).then(function() {
    raffleAddress = Raffle.address;
    Lotto.deployed().then(function(instance) {
    instance.initContract("0xf87d8a02199f40150de6ac04f2ced707bebaaedf",
      profitSplitterAddress,
      raffleAddress,
      "BM2hnCqNv0D2GGP9ztdJ2Hfd2QOdSlOzNGc5AdgtcKfkgh1ZfuRfmQ7qDzi4FNe67OPHzCjEIx+jfyEzhiYPG3bVCLS/z/Gzmh5vs2ATtDaoBvT3VKavTsFxUJMaoUwmS7DrSqcfxH2BorrNSXHatfIFYJvvy8Y=");
    });
  });
};
