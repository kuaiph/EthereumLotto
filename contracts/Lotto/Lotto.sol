pragma solidity ^0.4.10;

import "../../installed_contracts/oraclize/contracts/usingOraclize.sol";
import "../Raffle/Raffle.sol";

contract Lotto is usingOraclize {

  uint constant ORACLIZE_GAS_LIMIT = 400000;

  // Parts of the Oraclize Query String minus the encrypted Random.org API Key.
  string constant ORACLIZE_QUERY_START = "[URL] ['json(https://api.random.org/json-rpc/1/invoke).result.random.data.0', '\\n{\"jsonrpc\":\"2.0\",\"method\":\"generateSignedIntegers\",\"params\":{\"apiKey\":${[decrypt] ";
  string constant ORACLIZE_QUERY_END = "},\"n\":1,\"min\":1,\"max\":10000${[identity] \"}\"},\"id\":1${[identity] \"}\"}']";

  struct Ticket {
    uint16 numbers;
    address purchaser;
    bool redeemed;
  }

  enum State {
    Expired, // Lotto round has expired, tickets are no longer valid.
    Open, // Lotto round is open for ticket purchasing.
    Closed, // No tickets can be purchased for this lotto round.
    NumbersGenerated, // Winning numbers have been generated for this lotto round.
    Redeemable // Tickets for this lotto round are redeemable.
  }

  struct LottoRound {
    State state;  // State of this round
    uint startTime;
    uint endTime;
    uint houseCut; //
    uint ticketPrice;  // Ticket cost for this round, locked in at round initialization
    uint totalFunds;  // Total pool for player payouts
    uint totalPaidOut;  // Track amount paid out, so we can payout the remainder on withdrawl expiration
    uint16 winningNumbers;  // Winning numbers, set on round end
    uint8 payoutTableId;  // payout table & house cut to use (0 = Big-winner table + house cut, 1 = second-biggest winner table/cut, etc.) 
    mapping(address => uint[]) ticketsByAddress;  // Mapping of ticket ids purchased by each address
    Ticket[] tickets; // Array of all tickets puchased this round.
    uint ordered4WinnerCount;  // Number of ordered-4 winners, set on round end
    uint unordered4WinnerCount;  // Number of unordered-4 winners, set on round end
    uint ordered3WinnerCount;  // Number of ordered-3 winners, set on round end (first3 hits + last3 hits)
    uint ordered2WinnerCount;  // Number of ordered-2 winners, set on round end (first2 hits + last2 hits)
    address beneficiary; // address to pay house cut to, locked in at round initialization
  }

  uint8[4][5] payoutTables =[
    [85, 10, 4, 1],   // Payout table when we have 4-ordered winner
    [0, 70, 25, 5],   // Payout table when highest winner is 3-ordered
    [0, 0, 80, 20],   // Payout table when highest winner is 4-unordered
    [0, 0, 0, 100],   // Payout table when highest winner is 2-ordered
    [0, 0, 0, 0]];    // Payout table when no winner at all

  // Named constants to set which member of payoutTables[] and houseCutTable[] a round should use 
  uint8 constant ORDERED_4_ENTRY = 0; 
  uint8 constant ORDERED_3_ENTRY = 1;
  uint8 constant UNORDERED_4_ENTRY = 2;
  uint8 constant ORDERED_2_ENTRY = 3;
  uint8 constant NO_WINNERS_ENTRY = 4;

  uint8[5] houseCutTable = [10, 20, 30, 40, 100]; // 10% cut when we have big winner, 20% cut after first rolldown (assumes 90% rolldown), etc.

   modifier onlyOwner() { 
    require(owners[msg.sender] == 1); 
    _; 
  }

  modifier onlyOraclize {
    require(msg.sender == oraclize_cbAddress());
    _;
  }

  modifier onlyLottoService() {
    require(msg.sender == lottoServiceAddress);
    _;
  }

  modifier validNumbers(uint16 _numbers) {
    require(0 <= _numbers && _numbers <= 9999);
    _; 
  }

  modifier validPurchase(uint _value, uint _totalCost) {
    require(lottoRunning && lottoRounds[currentRound].state == State.Open);
    require(_value >= _totalCost);
    _;
  }

  modifier onlyPurchaser(uint _lottoRound, uint _ticketId) {
    require(msg.sender == lottoRounds[_lottoRound].tickets[_ticketId].purchaser);
    _;
  }

  modifier onlyRedeemableTicket(uint _lottoRound, uint _ticketId) {
    require(lottoRounds[_lottoRound].tickets[_ticketId].redeemed == false);
    _;
  }

  modifier inState(uint _lottoRound, State _state) {
    require(lottoRounds[_lottoRound].state == _state);
    _;
  }

  mapping(address => byte) public owners;

  // Address of function calls from the lotto service that provides
  // trusted random numbers for each drawing.
  address public lottoServiceAddress;

  address public beneficiary;
  mapping (address => uint) public beneficiaryFunds;

  // default houseCut as a percentage
  uint public houseCut;

  // fixed cost of a ticket is .01 ether
  uint public ticketPrice;
  
  /* Second-Chance Raffle Stuff */
  uint constant raffleCut = 1;  // percentage of winnings pool to set aside for second-chance raffle
  Raffle public raffleContract;  // address of second-chance raffle contract
  /* End Second-Chance Raffle Stuff */

  // Mapping of lottoRoundIds to LottoRound struct
  mapping(uint => LottoRound) public lottoRounds;

  uint public currentRound;
  bool public lottoRunning = false;

  // After this period a lotto round has expired and tickets can no longer be redeemed.
  uint public timeBeforeRoundExpiry; 
  uint public oldestActiveLottoRoundIndex;

  // The expected Oraclize Query ID for our latest request to Oraclize.
  bytes32 expectedOraclizeLottoQueryId;

  // Current Oraclize query string used to ask Oraclize for random numbers from Random.org.
  string oraclizeQuery;

  bool isInitialized = false;

  event LottoRoundClosed(uint lottoRound);
  event PrizeClaimed(uint lottoRound, address winner, uint value);
  event HouseCutAdded(uint lottoRound, address beneficiary, uint value);
  event BeneficiaryFundsWithdrawn(address beneficiary, uint value);
  event GeneratedQuickpick(uint16 generatedNumber);
  event BoughtTicket(address buyer, uint lottoRound, uint16 numbers);
  event WinningNumbersChosen(uint lottoRound, uint numbers);
  
  // Empty Debug events for Remix
  event RedeemOrdered4();
  event RedeemUnordered4();
  event RedeemFirstOrLast3();
  event RedeemFirstOrLast2();

  function Lotto() payable {
    owners[msg.sender] = byte(1);
  }

  function initContract(address _lottoServiceAddress, address _beneficiaryAddress, address _raffleAddress, string _encryptedRandomOrgApiKey) onlyOwner {
    require(!isInitialized); // Can only initialize once.

    isInitialized = true;

    // Remove this line when going into testnet or prod!
    OAR = OraclizeAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475);

    beneficiary = _beneficiaryAddress;

    timeBeforeRoundExpiry = 14 days; 
    oldestActiveLottoRoundIndex = 0;
    currentRound = 0;

    ticketPrice = 10 finney;
    houseCut = 20;

    // We want Oraclize to set the proof that they did what we asked them to do.
    oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);

    lottoServiceAddress = _lottoServiceAddress;
    lottoRunning = true;

    // Set our Oraclize Query String.
    changeRandomOrgApiKey(_encryptedRandomOrgApiKey);

    // Initialize required members of the first LottoRound struct
    lottoRounds[currentRound].houseCut = houseCut;
    lottoRounds[currentRound].ticketPrice = ticketPrice;
    lottoRounds[currentRound].beneficiary = beneficiary;
    lottoRounds[currentRound].totalFunds = 1;
    lottoRounds[currentRound].state = State.Open;
    lottoRounds[currentRound].startTime = now;

    // Link second-chance raffle contract
    raffleContract = Raffle(_raffleAddress);
  }

  /* buyTicket
   * @param _numbers - The numbers of the ticket being purchased in decimal format.
   *
   * Purchases a ticket and assigns it to the sender address' purchased ticket list
   * for this given round.
   * Validates that a ticket can be legitimately purchased.
   */
  function buyTicket(uint16 _numbers) validPurchase(msg.value, lottoRounds[currentRound].ticketPrice) validNumbers(_numbers) payable returns (uint) {    
    
    // Add the ticket to our array of tickets and add the ticket number (index of ticket)
    // to this addresses' purchased tickets mapping.
    var newLength = lottoRounds[currentRound].tickets.push(Ticket({
      numbers: _numbers,
      purchaser: msg.sender,
      redeemed: false
    }));
    lottoRounds[currentRound].ticketsByAddress[msg.sender].push(newLength - 1);

    lottoRounds[currentRound].totalFunds = 
      safeAdd(lottoRounds[currentRound].totalFunds, lottoRounds[currentRound].ticketPrice);

    BoughtTicket(msg.sender, currentRound, _numbers);
    refundOverage(lottoRounds[currentRound].ticketPrice);

    return currentRound;
  }

  /* quickPick
   *
   * Returns a 4-digit uint16 between 0000~9999 using the block timestamp, 
   * sender address, and number of tickets already purchased.
   */
  function quickPick() private returns (uint16 generatedNumber){
    generatedNumber = uint16(((uint(msg.sender) * (lottoRounds[currentRound].ticketsByAddress[msg.sender].length + 1)) / block.timestamp)%10000);
    GeneratedQuickpick(generatedNumber);
  }

  /* buyQuickPick
   *
   * Generates a 4-digit uint16 and buys a ticket with those 4 digits
   */
  function buyQuickPick() payable returns (uint roundNumber){
    uint16 nums = quickPick();
    roundNumber = buyTicket(nums);
    return roundNumber;
  }

  /* get100Tickets
   * @param _lottoRound - The lottery round to get tickets
   * @param _startOffset - The 0 indexed offset for fetching tickets
   *
   * Returns the count of tickets and batch of up to 100 tickets for a given round.
   * If the _startOffset is outside of the range of tickets, or if we land
   * on the "edge" of two buckets, return (0, empty array).
   */
  function get100Tickets(uint _lottoRound, uint _startOffset) onlyLottoService constant returns (uint batchCount, uint16[100] memory batch) {
    Ticket[] tickets = lottoRounds[_lottoRound].tickets;

    // process only if we are within a valid range.
    // otherwise, return (0, [])
    if (_startOffset < tickets.length) {
      // calculate how many tickets we will return with a max of 100
      batchCount = tickets.length - _startOffset;
      if (batchCount > 100) {
        batchCount = 100;
      }

      for (uint i = 0; i < batchCount; i++) {
        batch[i] = tickets[i + _startOffset].numbers;
      }
    }
    return (batchCount, batch);
  }

  /* getTotalTickets
   * @param _lottoRound - The lottery round to get total ticket counts for.
   *
   * Returns The total tickets purchased for the given round by the sender.
   */
  function getTotalTickets(uint _lottoRound) constant returns (uint) {
    return lottoRounds[_lottoRound].tickets.length;
  }

  /* getTicket
   * @param lottoRound - The lottery round to get the ticket for.
   * @param ticketNum - The number of the ticket to retrieve.
   *
   * Returns The ticketNum-th Ticket purchased by the sender for the given round.
   */
  function getTicket(uint _lottoRound, uint _ticketNum) constant returns(uint16) {
    require(_ticketNum < lottoRounds[_lottoRound].tickets.length);

    return lottoRounds[_lottoRound].tickets[_ticketNum].numbers;
  }

  /* refundOverage
   * @param totalCost - The total cost that is kept by the contract.
   *
   * Returns any additional value send by the sender back to the sender.
   */
  function refundOverage(uint _totalCost) internal {

    // TODO: Safe Subtract
    uint overageValue = msg.value - _totalCost;

    if (overageValue > 0) {
      msg.sender.transfer(overageValue);
    }
  }

  /* redeemTicket
   * @param _lottoRound - The lottery round to redeem ticket for.
   * @param _ticketNumber - The ticket number in the round to redeem
   *
   * Redeems sender's tickets for the specified lotto round and pays out
   */
  function redeemTicket(uint _lottoRound, uint _ticketId)
    inState(_lottoRound, State.Redeemable)
    onlyPurchaser(_lottoRound, _ticketId)
    onlyRedeemableTicket(_lottoRound, _ticketId) {

    uint ticketPayout = 0;
    LottoRound round = lottoRounds[_lottoRound];
    Ticket ticket = round.tickets[_ticketId];
    // We want to mark the ticket as redeemed as soon as possible
    // and regardless of whether or not it is a winner to also prevent
    // multiple raffle entries
    ticket.redeemed = true;

    // Start with the best possible payout for the player
    // and progressively check lower-tiered payouts only
    // if they haven't won
    ticketPayout = redeemOrdered4(round, ticket.numbers);
    if (ticketPayout == 0) {
      ticketPayout = redeemFirstOrLast3(round, ticket.numbers);
      if (ticketPayout == 0) {
        ticketPayout = redeemUnordered4(round, ticket.numbers);
        if (ticketPayout == 0) {
          ticketPayout = redeemFirstOrLast2(round, ticket.numbers);
        }
      }
    }

    // Transfer payout if there are winnings
    // or enter the player into the second chance raffle
    if (ticketPayout > 0) {
      round.totalPaidOut += ticketPayout;

      // Send ticket value to the redeemer. If this fails the redeemed flag set above will be rolled back.
      msg.sender.transfer(ticketPayout);

      // Fire off our PrizeClaimed event after the transfer completed successfully.
      PrizeClaimed(_lottoRound, msg.sender, ticketPayout);
    } else {
      raffleContract.addTicketFromLotto(msg.sender);
      // issue extra raffle if match first number
      if (ticket.numbers/1000 == round.winningNumbers/1000) {
        raffleContract.addTicketFromLotto(msg.sender);
      }
    }
  }

  /* redeemOrdered4
   * @param _round - The LottoRound to check ticket against.
   * @param _numbers - The ticket numbers to check.
   */
  function redeemOrdered4(LottoRound _round, uint _numbers) private returns (uint) {
    uint ticketValue = 0;
    if (_round.winningNumbers == _numbers) {
        // Winner!! Determine payout
        ticketValue = (_round.totalFunds * payoutTables[_round.payoutTableId][ORDERED_4_ENTRY]) / (100 * _round.ordered4WinnerCount);
        RedeemOrdered4();  // Empty debug event to see in Remix IDE
    }
    return ticketValue;
  }

  /* redeemUnordered4
   * @param _round - The LottoRound to check ticket against.
   * @param _numbers - The ticket numbers to check.
   */
  function redeemUnordered4(LottoRound _round, uint16 _numbers) private returns (uint) {
    uint ticketValue = 0;
    uint32 roundBit = toBits(_round.winningNumbers);
    uint32 ticketBit = toBits(_numbers);
    if (roundBit == ticketBit) {
        // Winner!! Determine payout
        ticketValue = (_round.totalFunds * payoutTables[_round.payoutTableId][UNORDERED_4_ENTRY]) / (100 * _round.unordered4WinnerCount);
        RedeemUnordered4();  // Empty debug event to see in Remix IDE
    }
    return ticketValue;
  }

  /* redeemFirstOrLast3
   * @param _round - The LottoRound to check ticket against.
   * @param _numbers - The ticket numbers to check.
   */
  function redeemFirstOrLast3(LottoRound _round, uint _numbers) private returns (uint) {
    uint ticketValue = 0;
    if ( ((_round.winningNumbers/10) == (_numbers/10)) || ((_round.winningNumbers%1000) == (_numbers%1000)) ) {
      // Winner!! Determine payout
      ticketValue = (_round.totalFunds * payoutTables[_round.payoutTableId][ORDERED_3_ENTRY]) / (100 * _round.ordered3WinnerCount);
      RedeemFirstOrLast3();
    }
    return ticketValue;
  }

  /* redeemFirstOrLast2
   * @param _round - The LottoRound to check ticket against.
   * @param _numbers - The ticket numbers to check.
   */
  function redeemFirstOrLast2(LottoRound _round, uint _numbers) private returns (uint) {
    uint ticketValue = 0;
    if ( ((_round.winningNumbers/100) == (_numbers/100)) || ((_round.winningNumbers%100) == (_numbers%100)) ) {
      // Winner!! Determine payout
      ticketValue = (_round.totalFunds * payoutTables[_round.payoutTableId][ORDERED_2_ENTRY]) / (100 * _round.ordered2WinnerCount);
      RedeemFirstOrLast2();
    }
    return ticketValue;
  }

  /* toBits
   * @param numbers - The decimal representation of a ticket to be encoded
   *
   * Returns the (unordered) bit representation of the 4 numbers as a single uint32
   */
  function toBits (uint16 _numbers) private returns (uint32 bitRep) {
    bitRep += uint32(1) << uint8(_numbers/(10**3))*3;
    bitRep += uint32(1) << uint8((_numbers % (10**3))/(10**2))*3;
    bitRep += uint32(1) << uint8((_numbers % (10**2))/10)*3;
    bitRep += uint32(1) << uint8(_numbers % 10)*3;
  }

  /* -------------------------------------------------------------------------- */
  /* ADMINISTRATIVE FUNCTIONS ONLY CALLABLE BY OWNER OR LOTTO SERVICE ADDRESSES */
  /* -------------------------------------------------------------------------- */

  /* closeTicketPurchasing
   *
   * Ends the ability for users to purchase tickets and kicks off the call to Oraclize to
   * generate the winning numbers.
   */
  function closeTicketPurchasing() onlyLottoService inState(currentRound, State.Open){
    lottoRounds[currentRound].state = State.Closed;
    generateWinningNumbers();
  }

  /* closeTicketPurchasingTest
   * @param _testWinningNumbers - TO BE REMOVED. For testing purposes to avoid Oraclize use.
   *
   * Test version of closeTicketPurchasing that allows winning numbers to be provided directly.
   * FOR TESTING PURPOSES ONLY. TO BE REMOVED
   */
  function closeTicketPurchasingTest(uint16 _testWinningNumbers) inState(currentRound, State.Open) {
    lottoRounds[currentRound].state = State.Closed;
    setWinningNumbers(_testWinningNumbers);
  }

  /* generateWinningNumbers (private)
   *
   * Calls out to Oraclize to generate the winning numbers.
   * There is the possibility that the Oraclize call fails before/during the __callback()
   * function execution.
   */
  function generateWinningNumbers() private inState(currentRound, State.Closed) {
    expectedOraclizeLottoQueryId = oraclize_query(
        "nested",
        oraclizeQuery,
        ORACLIZE_GAS_LIMIT
    );
  }

  /* __callback
   *
   * Dedicated callback method for Oraclize to call in to when it has retrieved the winning numbers.
   */
  function __callback(bytes32 _myid, string _result, bytes _proof) onlyOraclize {
    require(_myid == expectedOraclizeLottoQueryId);

    uint16 winningNumbers = uint16(parseInt(_result));
    setWinningNumbers(winningNumbers);
  }

  /* setWinningNumbers (private)
   * param _winningNumbers - The winning lotto numbers for the current lotto round.
   *
   * Sets the winning lotto numbers for the current round and fires the WinningNumbersChosen event.
   */
  function setWinningNumbers(uint16 _winningNumbers) private inState(currentRound, State.Closed) {
    LottoRound round = lottoRounds[currentRound]; 

    // Set winning numbers struct
    round.winningNumbers = _winningNumbers;

    round.state = State.NumbersGenerated;
    WinningNumbersChosen(currentRound, _winningNumbers);    
  }

  /* closeLottoRound
   * @param _ordered4WinnerCount - The number of tickets that matched all 4 numbers in correct order.
   * @param _unordered4WinnerCount - The number of tickets that matched all 4 numbers in any order.
   * @param _ordered3WinnerCount - The number of tickets that matched the first/last 3 numbers in correct order.
   * @param _ordered2WinnerCount - The number of tickets that matched the first/last 2 numbers in correct order.
   *
   * Ends the current round and saves the numbers of winners across each prize bucket. Starts the next round
   * and re-enables ticket purchasing.
   */
  function closeLottoRound(
      uint _ordered4WinnerCount,
      uint _unordered4WinnerCount,
      uint _ordered3WinnerCount,
      uint _ordered2WinnerCount) 
      onlyLottoService 
      inState(currentRound, State.NumbersGenerated) {
    LottoRound round = lottoRounds[currentRound];

    // Subtract 1 from this round's total funds as we initialized the value to
    // 1 during the initialization of the round (to avoid first-ticket-purchase gas costs).
    round.totalFunds -= 1;

    round.ordered4WinnerCount = _ordered4WinnerCount;
    round.unordered4WinnerCount = _unordered4WinnerCount;
    round.ordered3WinnerCount = _ordered3WinnerCount;
    round.ordered2WinnerCount = _ordered2WinnerCount;

    // Set the payout table to use based on how much we rolldown
    if (round.ordered4WinnerCount > 0){
      // Biggest winner is ordered-4
      round.payoutTableId = ORDERED_4_ENTRY;
    } else if (round.ordered3WinnerCount > 0){
      // Biggest winner is ordered-3
      round.payoutTableId = ORDERED_3_ENTRY;
    } else if (round.unordered4WinnerCount > 0){
      // Biggest winner is unordered-4
      round.payoutTableId = UNORDERED_4_ENTRY;
    } else if (round.ordered2WinnerCount > 0){
      // Biggest winner is ordered-2
      round.payoutTableId = ORDERED_2_ENTRY;
    } else {
      // No winners, all goes to beneficiary
      round.payoutTableId = NO_WINNERS_ENTRY;
    }

    // Take small chunk of winnings for Second Chance pool
    uint rafflePayout = round.totalFunds * raffleCut / 100;
    round.totalFunds -= rafflePayout;  //TODO: SafeSubtract
    raffleContract.transfer(rafflePayout);

    // Send the house cut immediately.
    sendHouseCut(round);

    // Open up redemption for this round
    round.state = State.Redeemable;
    round.endTime = now;

    initNextRound();
  }

  /* initNextRound
   *
   * Increase the currentRound count and initialize the required members of
   * the LottoRound struct.
   */
  function initNextRound() private inState(currentRound, State.Redeemable){
    currentRound++;
    lottoRounds[currentRound].houseCut = houseCut;
    lottoRounds[currentRound].ticketPrice = ticketPrice;
    lottoRounds[currentRound].beneficiary = beneficiary;
    lottoRounds[currentRound].state = State.Open;
    lottoRounds[currentRound].startTime = now;

    // If we don't initialize this to some non-zero value the very first ticket purchase incurs an additional 
    // 20k gas! We will subtract this value out during the closing of the round.
    lottoRounds[currentRound].totalFunds = 1;

    // Also try to expire the oldest still-active lotto round to free up the storage.
    expireOldestActiveLottoRound();
  }

  /* expireOldestActiveLottoRound
   *
   * Attempts to expire the oldest active lotto round.
   */
  function expireOldestActiveLottoRound() private {
    LottoRound round = lottoRounds[oldestActiveLottoRoundIndex];

    // If we're looking at a lotto round that is not redeemable then it's not a candidate for expiry.
    if (round.state != State.Redeemable) {
      return;
    }

    // Safety check here to cover future code changes that may impact when endTime is set.
    if (round.endTime == 0) {
      return;
    }

    // Test if the time between now and when the round ended is greater than the total time a round can
    // be in the redeemable state for.
    if (now - round.endTime < timeBeforeRoundExpiry) {
      // We're still below the time before round expiry so get outta here.
      return;
    }

    // First, take all the un-redeemed proceeds and add them to the beneficiary payout...
    uint remainingFunds = round.totalFunds - round.totalPaidOut;
    beneficiaryFunds[beneficiary] = safeAdd(beneficiaryFunds[beneficiary], remainingFunds);

    // And then clean up the lotto round.
    delete lottoRounds[oldestActiveLottoRoundIndex];
    oldestActiveLottoRoundIndex++; // We've removing this lotto round so move on to the next one in the future.
  }

  /* sendHouseCut
   * @param round - The LottoRound to send a house cut for.
   *
   * Sends the house cut for the given LottoRound to the beneficiary address.
   */
  function sendHouseCut(LottoRound _round) private {
    // Payout to beneficiary and subtract this from the round's totalFunds
    uint housePayout = _round.totalFunds * houseCutTable[_round.payoutTableId] / 100;
    _round.totalFunds -= housePayout;
    beneficiaryFunds[beneficiary] = safeAdd(beneficiaryFunds[beneficiary], housePayout);
    HouseCutAdded(currentRound, _round.beneficiary, housePayout);
  }

  /* changeBeneficiary
   * @param _newBeneficiary - Address of the new beneficiary to receive house cut payout
   *
   * Sets the beneficiary, only affects lotto rounds initialized AFTER this change is made
   */
  function changeBeneficiary(address _newBeneficiary) onlyOwner {
    beneficiary = _newBeneficiary;
  }

  /* changeHouseCut
   * @param _newHouseCut - New house cut as a percentage
   *
   * Sets the house cut, only affects lotto rounds initialized AFTER this change is made
   */
  function changeHouseCut(uint _newHouseCut) onlyOwner {
    houseCut = _newHouseCut;
  }

  /* changeTicketPrice
   * @param _newPrice - New price per ticket (in wei)
   *
   * Sets the ticket price, only affects lotto rounds initialized AFTER this change is made
   */
  function changeTicketPrice(uint _newTicketPrice) onlyOwner {
    ticketPrice = _newTicketPrice;
  }

  /* changeRandomOrgApiKey
   * @param _encryptedApiKey - The API Key for Random.org encrypted via http://app.oraclize.it/home/test_query
   *                           !!!IMPORTANT!!! When regenerating the key on that site WRAP IN DOUBLE QUOTES "
   *
   * Replaces the current Random.org API Key in the Oraclize Query String with the new one.
   */
  function changeRandomOrgApiKey(string _encryptedApiKey) onlyOwner {
    oraclizeQuery = strConcat(ORACLIZE_QUERY_START, _encryptedApiKey, ORACLIZE_QUERY_END);
  }

  /* changeRaffleContract
   * @param _newRaffleContract - Address of new second-chance raffle contract
   *
   * Sets the raffle contract, affects all future raffle tickets issued
   */
  function changeRaffleContract(address _newRaffleContract) onlyOwner {
    raffleContract = Raffle(_newRaffleContract);
  }

  /* payoutBeneficiaryFunds
   *
   * Pays out the current funds to the beneficiary address.
   * EXPLICITLY PUBLIC AS BENEFICIARY ADDRESS IS SET IN CONTRACT AND NOT PROVIDED AS INPUT
   * TO THIS FUNCTION.
   */
  function payoutBeneficiaryFunds(address beneficiary) public {
    require(beneficiaryFunds[beneficiary] > 0);

    uint funds = beneficiaryFunds[beneficiary];
    beneficiaryFunds[beneficiary] = 0;

    bool success = beneficiary.call.value(funds)();

    require(success);

    BeneficiaryFundsWithdrawn(beneficiary, beneficiaryFunds[beneficiary]);
  }

  /* safeAdd
   * @param baseValue - The base value we are starting with
   * @param toAdd - The value to attempt to add to baseValue.
   *
   * Attempts to add toAdd to baseValue. If overflow occurs, returns baseValue.
   * Otherwise returns baseValue + toAdd.
   */
  function safeAdd(uint baseValue, uint toAdd) returns (uint sum) {
    if (baseValue + toAdd > baseValue) {
      sum = baseValue + toAdd;
    } else {
      sum = baseValue;
    }
  }

  // Default function.
  // If not sent from an owner address, throw.
  function() payable onlyOwner {
  }
}
