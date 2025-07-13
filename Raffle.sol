//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/src/v0.8/VRFConsumerBaseV2.sol";
// import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
// import {AutomatinCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomatinCompatibleInterface.sol";


// import {VRFCoordinatorV2Interface} from "lib/trial.sol";
// import {VRFConsumerBaseV2} from "lib/trial2.sol";




/**
 * @title  Raffle contract
 * @author Quraishi Abdur Rahman
 * @notice This contract is for creating a sample Raffle
 * @dev It implements Chainlink VRFv2
 */
 

contract Raffle is VRFConsumerBaseV2{

    /** ERROR MESSAGE */
    error NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);
    // error Raffle__NotEnoughEthSent();


    /**Type declarations */
    enum RaffleState {
        OPEN,         //0
        CALCULATING  //1
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    // ABove we used uppercase as it is the const and using uppercase is gas efficient..

    uint256 private immutable i_entranceFee;
    // @dev duration of the lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    // we choosed s_players i.e, state variable rather immutable as it will be changing with users
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;

    RaffleState private s_raffleState;

    /** EVENTS */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);


    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN; 
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not Enough Eth Sent");
        // Above is gas inefficient whereas below is efficient and alternative of above code line
        if (msg.value < i_entranceFee) {
            revert NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN){
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
/**So in smart contract whenever someone calls store function we are going to emit the event
    and how to do it is specified in L9 P4 of yt*/

    //So why these events are useful like why we are emitting it?
    // 1. Makes migration easier
    // 2. Makes front end "indexing" easier
    emit EnteredRaffle(msg.sender);

    }
    // When is the winner is supposed to get picked?
    /***
    * @dev This is the function that the Chainlink automation nodes call to see 
    * if it's time to perform an upkeep..
    * The following should be true for this to return true:
    ** 1. The time interval has passed b/w raffle runs..
    ** 2. The raffle is in the open state..
    ** 3. The contract has ETH (aka, players)..
    ** 4. (IMPLICIT) The subscription is funded with LINK
    * @param null
    * @return upkeepNeeded
    * @return
     */
    
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (( block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // 1. TO get a random number
    // 2. then use this random no. to pick a player
    // 3. And be automatically called

    // function pickWinner() external {
        function performUpkeep(bytes calldata /* performData */) external {
            (bool upkeepNeeded, ) = checkUpkeep("");
            if (!upkeepNeeded) {
                revert Raffle__UpkeepNotNeeded(
                    address(this).balance,
                    s_players.length,
                    uint256(s_raffleState)
                );
            }

    //    if(( block.timestamp - s_lastTimeStamp) < i_interval) {
    //     revert();
    //    }
        s_raffleState = RaffleState.CALCULATING;

    /** Requesting chainlink node to give us a random number */
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            // keyHash, -----> gas lane
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
       // It is reduntant???.....
       emit RequestedRaffleWinner(requestId);
    }

    // CEI: Checks, Effects, Interactions

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        // CHECKS
        // EFFECTS (Our own contract)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        // after getting winner opening the raffle state by next command
        s_raffleState = RaffleState.OPEN;

        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);
        // INTERACTIONS (other contracts)

        (bool success ,) = winner.call{value: address(this).balance}("");
        if (!success){ // means failed
            revert Raffle__TransferFailed();
        }
        
    }
    
    /** getter function */

    function getEntranceFee() external view returns (uint256){
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) public view returns (address) {
    return s_players[0];
    } // this was added by gpt

}