# Ethereum Lotto

Simple set of contracts to enable a lottery service on Ethereum. Features:

(1) Off-chain RNG via Oraclize -> Random.org to avoid miners impacting the RNG if it was on-chain. (This involves additional trust, of course).
(2) Additional second-chance raffle to allow losing ticket holders another chance at winning from a smaller pool.

## Testing via TestRPC

* Truffle Migrations are currently set up to initialize with a static lottoServiceAddress.
* When running via testrpc, launch with the following command:

```testrpc --account "0xad2d6c4bc6df63e2a075f5ca8e2553e1f6a7c463bae25e43ea9bf56e69307ba3,1000000000000000000000000" --account "0xc1c01d90b7e725538a5cf47fc94e190df92a460bce8ff932a95c5b3e02a300f9,100000000000000000000" --account "0xe58e463da40b1184a2a0594deb3583b95386c4b8abc3909cdc226576274b64d0,100000000000000000000", --account "0x44ab6c6d6340905c04679933b2f6afec7d1c28f1eceb467f65148f1e2e9f733c,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87098,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87097,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87096,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87095,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87094,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87093,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87092,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87091,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87090,100000000000000000000" --account "0xc0ac96aad56103a655620f4c07dfe1a99da64e62b6428ec2914a9d6a02f87089,100000000000000000000" --gasLimit 0x6B8D80```

* The first account listed is the one used as the lottoServiceAddress.

## Other helpful operations from truffle console:

- Reference the contract: ```var c = Lotto.at("ADDRESS_DURING_MIGRATE")```
- Initialize the contract (replace second address with that of the deployed ProfitSplitter contract): ```c.initContract("0xf87d8a02199f40150de6ac04f2ced707bebaaedf", "0xf87d8a02199f40150de6ac04f2ced707bebaaedf", "BM2hnCqNv0D2GGP9ztdJ2Hfd2QOdSlOzNGc5AdgtcKfkgh1ZfuRfmQ7qDzi4FNe67OPHzCjEIx+jfyEzhiYPG3bVCLS/z/Gzmh5vs2ATtDaoBvT3VKavTsFxUJMaoUwmS7DrSqcfxH2BorrNSXHatfIFYJvvy8Y=")```
- Purchase a single ticket from current account (web3.eth.accounts[0] by default): ```c.buyTicket(1234, {value: 10000000000000000})```
- Purchase a single ticket from another account: ```c.buyTicket(1234, {from: "0xADDRESS",value:1000000000000000})```
