pragma solidity ^0.4.0;

//TODO: Add oraclize for determining raffle winner in-contract

contract Raffle {

    address[] public raffleTickets;  // Array addresses used for second-chance raffle draw
    uint public fundsAwaitingWithdrawl;  // Raffle Payouts that have not been withdrawn yet
    mapping(address => uint) public raffleWinnerWithdrawls;  // mapping for raffle winner to withdraw their winnings
    address owner;  // Probably a good idea to restrict stuff?
    address lottoContract;  // Address of main lotto contract
    address raffleService;  // Likely same as LottoService from the main contract

    event RaffleWinner(address winner, uint value);
    event RaffleTicketIssued(address entrant);
    event RafflePrizeWithdrawn(address winner, uint value);
    event InsufficientFunds(address winner, uint attemptedWithdrawl, uint currentBalance);

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyLottoContract() {
        require(msg.sender == lottoContract);
        _;
    }

    modifier onlyRaffleService() {
        require(msg.sender == raffleService);
        _;
    }

    function Raffle(address _lottoContract){
        owner = msg.sender;
        raffleService = owner;  // By default, raffleService is owner I guess?
        lottoContract = _lottoContract;
    }

    /* addTicketFromLotto
     *
     * @param _addr - The player address to add a ticket for
     */
    function addTicketFromLotto(address _addr) onlyLottoContract {
        raffleTickets.push(_addr);
        RaffleTicketIssued(_addr);
    }

    /* withdrawRaffleWinnings
     *
     * Withdraws any raffle winnings the sending address has to their name
     */
    function withdrawRaffleWinnings() {
        uint winnings = raffleWinnerWithdrawls[msg.sender];
        if (winnings > 0) {
            if (winnings <= this.balance){
                raffleWinnerWithdrawls[msg.sender] = 0;
                msg.sender.transfer(winnings);
                fundsAwaitingWithdrawl = SafeSubtract(fundsAwaitingWithdrawl, winnings);
                RafflePrizeWithdrawn(msg.sender, winnings);
            } else {
                // Sanity check, shouldn't get here unless someone finds an exploit and withdraws too much...
                InsufficientFunds(msg.sender, winnings, this.balance);
            }
        }
    }

    /* getCurrentRafflePool
     *
     * Returns the amount of the current raffle pool
     */
    function getCurrentRafflePool() constant returns (uint){
        return SafeSubtract(this.balance, fundsAwaitingWithdrawl);
    }

    //TODO MAKE THIS PRIVATE AND ONLY CALLED FROM ORACLIZE CALLBACK!
    /* setRaffleWinner
     * @param _winningIndex - Index of raffleTickets[] array that contains the winning address
     *
     * Allocates the current raffle pool to the address at raffleTickets[_winningIndex],
     * then zeroes out the raffleTickets array
     */
    function setRaffleWinner(uint _winningIndex) onlyRaffleService {
        require(_winningIndex < raffleTickets.length);

        uint rafflePool = getCurrentRafflePool();
        address winner = raffleTickets[_winningIndex];
        RaffleWinner(winner, rafflePool);
        raffleWinnerWithdrawls[winner] = SafeAdd(raffleWinnerWithdrawls[winner], rafflePool);
        fundsAwaitingWithdrawl = SafeAdd(fundsAwaitingWithdrawl, rafflePool);
        delete raffleTickets;
    }

    /* changeLottoContract
     * @param _newLottoContract - address of new Lotto Contract that will be generating tickets
     *
     */
    function changeLottoContract(address _newLottoContract) onlyOwner {
        lottoContract = _newLottoContract;
    }

    /* changeRaffleService
     * @param _newRaffleService - address of new Raffle Service
     *
     */
    function changeRaffleService(address _newRaffleService) onlyOwner {
        raffleService = _newRaffleService;
    }

    /* SafeAdd
     * @param a - first number to add
     * @param b - second number to add
     *
     * Returns a+b, or reverts if there is an overflow
     */
    function SafeAdd(uint a, uint b) returns (uint c){
        c = a + b;
        require (c >= a);
        return c;
    }

    /* SafeSubtract
     * @param a - Starting amount
     * @param b - Amount to subtract
     *
     * Returns a-b, or reverts if there is an underflow
     */
    function SafeSubtract(uint a, uint b) returns (uint){
        require (b <= a);
        return (a - b);
    }

    function () payable {}
}
