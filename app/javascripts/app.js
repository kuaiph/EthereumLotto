// Import the page's CSS. Webpack will know what to do with it.
import "../stylesheets/app.css";

// Import libraries we need.
import { default as Web3} from 'web3';
import { default as contract } from 'truffle-contract'

// Import our contract artifacts and turn them into usable abstractions.
import lottoArtifacts from '../../build/contracts/Lotto.json'

// Lotto is our usable abstraction, which we'll use through the code below.
var Lotto = contract(lottoArtifacts);

// The following code is simple to show off interacting with your contracts.
// As your needs grow you will likely need to change its form and structure.
// For application bootstrapping, check out window.addEventListener below.
var accounts;
var account;

window.App = {
  start: function() {
    var self = this;

    // Bootstrap the Lotto abstraction for Use.
    Lotto.setProvider(web3.currentProvider);

    // Get the initial account balance so it can be displayed.
    web3.eth.getAccounts(function(err, accs) {
      if (err != null) {
        alert("There was an error fetching your accounts.");
        return;
      }

      if (accs.length == 0) {
        alert("Couldn't get any accounts! Make sure your Ethereum client is configured correctly.");
        return;
      }

      accounts = accs;
      account = accounts[0];

      self.updateRoundInfo();
    });
  },

  setStatus: function(message) {
    console.log(message);
    var status = document.getElementById("status");
    status.innerHTML = message;
  },

  updateRoundInfo: function() {
    var numberLabel = document.getElementById("roundLabel");
    var priceLabel = document.getElementById("priceLabel");
    var stateLabel = document.getElementById("stateLabel");
    var lotto;
    Lotto.deployed().then(function(instance){
        lotto = instance;
        return lotto.currentRound.call();
    }).then(function(res){
        numberLabel.innerHTML = res;
        return lotto.lottoRounds.call(res); //TODO get price for the round, not the global "price"
    }).then(function (res){
        priceLabel.innerHTML = web3.fromWei(res[4], "Ether") + " Ether";
        stateLabel.innerHTML = res[0];
    });
  },

  buyTicket: function() {
    var nums = parseInt(document.getElementById("ticketNums").value);
    Lotto.deployed().then(function(instance){
        instance.buyTicket(nums, {from:account, value:web3.toWei(0.1, "Ether"), gas:120000});
    });
  },

  buyQuickPick: function() {
    Lotto.deployed().then(function(instance){
        instance.buyQuickPick({from:account, value:web3.toWei(0.1, "Ether"), gas:120000});
    });
  },

  closeRound: function() {
    Lotto.deployed().then(function(instance){
        instance.closeTicketPurchasing({from:account, gas:200000});
    });
  },

  closeRoundDebug: function() {
    var winningNumbers = parseInt(document.getElementById("winningNums").value);
    Lotto.deployed().then(function(instance){
        instance.closeTicketPurchasingTest(winningNumbers, {from:account});
    });
  },

  finalizeRound: function() {
    var self = this;
    var lotto;
    var allTickets;
    var winningNumbers;

    Lotto.deployed().then(function(instance){
        lotto = instance;
        // get current round number
        return lotto.currentRound.call()
    }).then(function(currentRound){
        // get all tickets for this round from contract
        return Promise.all([self.getAllTickets(currentRound), lotto.lottoRounds(currentRound)]);
    }).then(function([allTicketsArray, lottoRoundStruct]){
        if (parseInt(lottoRoundStruct[0]) != 2){
            //TODO STOP HERE, WE HAVE NOT GENERATED WINNING NUMBERS YET! THROW EXCEPTION OR SOMETHING?
            console.log("IN WRONG STATE! Should be '2', but we're in state: " + lottoRoundStruct[0]);
        }
        allTickets = allTicketsArray;
        winningNumbers = parseInt(lottoRoundStruct[7]);
        console.log("winning numbers: " + winningNumbers);
        console.log("all tickets: " + allTickets);
        // Process all tickets off-contract to determine winners
        var winnerCounts = self.processTickets(allTickets, winningNumbers)
        console.log("DEBUG: Winner counts are...");
        console.log("DEBUG: ordered-4: " + winnerCounts[0]);
        console.log("DEBUG: ordered-3: " + winnerCounts[1]);
        console.log("DEBUG: unordered-4: " + winnerCounts[2]);
        console.log("DEBUG: ordered-2: " + winnerCounts[3]);
        // CloseLottoRound on-contract once processing is complete
        lotto.closeLottoRound(winnerCounts[0], winnerCounts[1], winnerCounts[2], winnerCounts[3], {from:account, gas:300000});
    });
  },

  getAllTickets: async function(roundNum) {
    var self = this;
    var ticketNums = [];
    var offset = 0;
    var length = 0;
    var i = 0;
    var ticketBundle;
    do {
        ticketBundle = await self.getTicketBundle(roundNum, offset);
        length = parseInt(ticketBundle[0]);
        console.log("ticketBundle has length:" + length + " and tickets: " + ticketBundle[1]);
        for (i=0; i<length; i++){
            ticketNums[i + offset] = parseInt(ticketBundle[1][i]);
        }
        offset += length;
    } while (length == 100);

    return ticketNums;
  },

  getTicketBundle: function(roundNum, offset){
  return Lotto.deployed().then(function(lotto){
         return lotto.get100Tickets(roundNum, offset);
     }).then(function(ret){
         return ret;
     });
  },

  compareMaps: function(map1, map2){
    if (Object.keys(map1).length != Object.keys(map2).length){
        return false;
    }

    for (var key in Object.keys(map1)){
        if (map1[key] != map2[key]){
            return false;
        }
    }

    return true;
  },

  toDigitMap: function(numbers){
    var digitMap = {};
    // Get raw digits
    var rawDigits = [Math.floor(numbers/1000)];
    rawDigits.push(Math.floor((numbers%1000)/100));
    rawDigits.push(Math.floor((numbers%100)/10));
    rawDigits.push(Math.floor(numbers%10));

    for (var i = 0; i<rawDigits.length; i++){
        digitMap[rawDigits[i]] = digitMap[rawDigits[i]]===undefined ? 1 : digitMap[rawDigits[i]]+1;
    }
    return digitMap;
  },

  processTickets: function(tickets, winningNumbers){
    var self = this;
    var winnerCounts = [0, 0, 0, 0]; //array to tally the counts for each type of winner (ordered 3, unordered 4, ordered 3, ordered 2)
    var count = tickets.length;
    var t;
    // get hashmap of winning digits and their counts
    var winDigitsMap = self.toDigitMap(winningNumbers);

    //TODO: Store ticket array position of each winner, so we can lookup the winner addresses later
    for (var i = 0; i<count; i++){
        t = tickets[i];
        console.log("DEBUG: Checking ticket: " + t);
        // Check ordered-4
        if (t == winningNumbers){
            console.log("DEBUG: Found ordered-4 winner: " + t);
            winnerCounts[0] += 1;
            continue;
        }

        // Check ordered-3
        if ((Math.floor(t/10) == Math.floor(winningNumbers/10)) || (t%1000 == winningNumbers%1000)) {
            console.log("DEBUG: Found ordered-3 winner: " + t);
            winnerCounts[1] += 1;
            continue;
        }

        // Check unordered-4
        var tickDigitsMap = self.toDigitMap(t);
        if (self.compareMaps(tickDigitsMap, winDigitsMap)){
            console.log("DEBUG: Found unordered-4 winner: " + t);
            winnerCounts[2] += 1;
            continue;
        }

        // Check ordered-2
        if ((Math.floor(t/100) == Math.floor(winningNumbers/100)) || (t%100 == winningNumbers%100)) {
            console.log("DEBUG: Found ordered-2 winner: " + t);
            winnerCounts[3] += 1;
            continue;
        }
    }
    return winnerCounts;
  },

  getRoundInfo: function(){
    var roundNum = parseInt(document.getElementById("roundLookup").value);
    var infoLabel = document.getElementById("roundInfo");
    Lotto.deployed().then(function(instance){
        return instance.lottoRounds.call(roundNum);
    }).then(function(roundInfo){
        infoLabel.innerHTML = "<b>STATE:</b> " + roundInfo[0] +
                              "<br><b>START TIME:</b> " + roundInfo[1] +
                              "<br><b>END TIME:</b> " + roundInfo[2] +
                              "<br><b>HOUSE CUT:</b> " + roundInfo[3] +
                              "<br><b>TICKET PRICE:</b> " + roundInfo[4] +
                              "<br><b>TOTAL FUNDS:</b> " + roundInfo[5] +
                              "<br><b>TOTAL PAID OUT:</b> " + roundInfo[6] +
                              "<br><b>WINNING NUMBERS:</b> " + roundInfo[7] +
                              "<br><b>PAYOUT TABLE ID:</b> " + roundInfo[8] +
                              "<br><b>ORDERED-4 WINNERS:</b> " + roundInfo[9] +
                              "<br><b>ORDERED-3 WINNERS:</b> " + roundInfo[10] +
                              "<br><b>UNORDERED-4 WINNERS:</b> " + roundInfo[11] +
                              "<br><b>ORDERED-2 WINNERS:</b> " + roundInfo[12] +
                              "<br><b>BENEFICIARY:</b> " + roundInfo[13];
    });

  }
};

window.addEventListener('load', function() {
  // Checking if Web3 has been injected by the browser (Mist/MetaMask)
  if (typeof web3 !== 'undefined') {
    console.warn("Using web3 detected from external source. If you find that your accounts don't appear or you have 0 ETH, ensure you've configured that source properly. If using MetaMask, see the following link. Feel free to delete this warning. :) http://truffleframework.com/tutorials/truffle-and-metamask")
    // Use Mist/MetaMask's provider
    window.web3 = new Web3(web3.currentProvider);
  } else {
    console.warn("No web3 detected. Falling back to http://localhost:8545. You should remove this fallback when you deploy live, as it's inherently insecure. Consider switching to Metamask for development. More info here: http://truffleframework.com/tutorials/truffle-and-metamask");
    // fallback - use your fallback strategy (local node / hosted node + in-dapp id mgmt / fail)
    window.web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));
  }

  App.start();
});
