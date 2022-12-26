//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// INIT FLOW //
// User enroll, inpit their datas
// Direct payment registration fee
// Get static premium
// Data listed on beneficiary data, owner can check registered devices

contract MangoCare {
    address payable owner;
    uint256 internal insuranceRecievedBalance;

    /*
      amount user should pay each claim process
    */
    uint256 public premiumPerAccident = 0.1 ether;
    /*
      First time payment to join the insurance program
     */
    uint256 public staticPremiumPerEnrollment = 1 ether;

    receive() external payable {}

    fallback() external payable {}

    constructor() {
        owner = payable(msg.sender);
    }

    struct Product {
        uint256 serialNo;
        string gadgetType;
    }

    enum Reason {
        Software,
        Hardware,
        Stolen,
        ForceMajure,
        Uindentified
    }

    /*
        Data structure for order history from customer
    */
    struct ClaimSubmission {
        address claimAddress; // address used by the user to claim insurance
        /*
            Enum for reason
            0 = Software, 1 = Hardware, 2 = Stolen, 3 = ForceMajure, 4 = Uindentified
        */
        Reason claimReason;
        uint256 eventTime; // If the happening time is more than 7 days, cannot claim. time in epoch
        uint256 premiumPaid; // premium paid by customer in ether this claim
        uint256 claimedAt; // the time that the customer submit the claim
    }

    struct Beneficiary {
        address ownerAddress;
        string firstName;
        string lastName;
        // bool banned;
        // bool policyValid;
        uint256 lastPayment;
        uint256 numAccidents;
        Product product;
        ClaimSubmission[] claims; // insurance order history for a specific flight
    }

    function isSerialDuplicate(uint256 _sn)
        public
        view
        returns (bool _registered)
    {
        for (uint256 i = 0; i < registeredSerialNumbers.length; i++) {
            if (registeredSerialNumbers[uint256(i)] == _sn) {
                return true;
            }
        }
    }

    /*
      First time insurance registration payment
    */

    function payForEnrollment() public payable {
        payable(address(this)).transfer(staticPremiumPerEnrollment);
        insuranceRecievedBalance += staticPremiumPerEnrollment;
    }

    /* 
        Only insurance company can make the changes
    */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can access this function");
        _;
    }

    function getContractBalance() public view onlyOwner returns (uint256) {
        return address(this).balance;
    }

    /*
        Map registration info to the beneficiary Data
    */
    mapping(address => Beneficiary) public beneficiaryData;
    uint256[] internal registeredSerialNumbers;

    /*
        Owner checks listed serial number
    */
    function getRegisteredDevices()
        public
        view
        onlyOwner
        returns (uint256[] memory devices)
    {
        return registeredSerialNumbers;
    }

    function getHistoricalData(address _custAddress)
        public
        view
        onlyOwner
        returns (ClaimSubmission[] memory claims)
    {
        return beneficiaryData[_custAddress].claims;
    }

    /*
      Register as new user
    */
    function applyForInsurance(
        address _custAddress,
        string memory _firstName,
        string memory _lastName,
        uint256 _serialNo,
        string memory _gadgetType
    ) public payable {
        require(
            !isSerialDuplicate(_serialNo),
            "This serial number is already asscociated with a policy"
        );
        beneficiaryData[_custAddress].ownerAddress = _custAddress;
        beneficiaryData[_custAddress].firstName = _firstName;
        beneficiaryData[_custAddress].lastName = _lastName;
        beneficiaryData[_custAddress].product.serialNo = _serialNo;
        beneficiaryData[_custAddress].product.gadgetType = _gadgetType;

        registeredSerialNumbers.push(_serialNo);

        require(
            msg.value >= staticPremiumPerEnrollment,
            "Please pay with sufficient credit"
        );
        payForEnrollment();
    }

    /*
        Claim the insurance
    */
    // Check whether serial number exist for user claiming
    // Check number of claim
    // If number of claim > 5 count with multiplication. Else pay static fee
    // Check for reason, if unindentified, use random logic to approve anot
    // Accept claim, add no of claim, add paid premium by company
    function claim(
        address _custAddress,
        uint256 _serialNo,
        uint256 _reason,
        uint256 _eventTime
    ) public payable returns (string memory claimMsg) {
        // Claim validation
        require(
            isLessThanAWeek(_eventTime),
            "You can only claim event that occured 7 days back!"
        );

        ClaimSubmission memory _currClaim; // temporary struct to be pushed
        _currClaim.claimAddress = msg.sender;
        _currClaim.premiumPaid = 0;
        _currClaim.eventTime = _eventTime;
        _currClaim.claimedAt = block.timestamp;

        if (_reason == 0) {
            _currClaim.claimReason = Reason.Software;
        } else if (_reason == 1) {
            _currClaim.claimReason = Reason.Hardware;
        } else if (_reason == 2) {
            _currClaim.claimReason = Reason.Stolen;
        } else if (_reason == 3) {
            _currClaim.claimReason = Reason.ForceMajure;
        } else if (_reason >= 4) {
            _currClaim.claimReason = Reason.Uindentified;
        }

        uint256 _numAcc = beneficiaryData[address(_custAddress)].numAccidents;
        uint256 _sn = beneficiaryData[address(_custAddress)].product.serialNo;
        require(
            _sn == _serialNo,
            "You don't have any insured product under the serial number"
        );
        if (_sn == _serialNo) {
            /*
                If claim reason is unindentified, proceed with "dummy" manual checker. If can be insured
                will continue normal claim process. Otherwise process stops here
            */
            if (_currClaim.claimReason == Reason.Uindentified) {
                uint256 randNonce = 0;
                uint256 random = uint256(
                    keccak256(
                        abi.encodePacked(block.timestamp, msg.sender, randNonce)
                    )
                ) % 100;
                bool isPassedManualCheck = random % 2 == 0;
                require(
                    isPassedManualCheck,
                    "Your claim reason is not approved, please submit another claim"
                );
            }

            if (_numAcc > 5) {
                // Multiplies with times of acc
                uint256 newPremiumPerAccident = 0.1 ether;
                _currClaim.premiumPaid = newPremiumPerAccident * _numAcc;
            } else if (_numAcc >= 10) {
                // Static pricier premium if more than 10 claims
                uint256 newPremiumPerAccident = 1 ether;
                _currClaim.premiumPaid = newPremiumPerAccident;
            } else {
                _currClaim.premiumPaid = premiumPerAccident;
            }

            require(
                msg.value >= _currClaim.premiumPaid,
                string(
                    abi.encodePacked(
                        "Please deposit the correct premium, your minimum payment is ",
                        Strings.toString(_currClaim.premiumPaid)
                    )
                )
            );
            // Save recieved balance
            insuranceRecievedBalance += _currClaim.premiumPaid;
            // Pay to this contract
            payable(address(this)).transfer(_currClaim.premiumPaid);
            // Add claim count each time
            beneficiaryData[address(_custAddress)].numAccidents += 1;
            //  Save claim history
            beneficiaryData[_custAddress].claims.push(_currClaim);
            // Save last payment time
            beneficiaryData[address(_custAddress)].lastPayment = block
                .timestamp;
            return "Success claim";
        } else {
            return "Serial number does not exist";
        }
    }

    function unregister(address _custAddress) public {
        uint256 _sn = beneficiaryData[_custAddress].product.serialNo;
        delete beneficiaryData[_custAddress];

        deleteSerialNo(_sn);
    }

    function deleteSerialNo(uint256 _serialNo) private {
        uint256 snLength = registeredSerialNumbers.length;
        uint256 j = 0;
        uint256 index;

        while (j < snLength) {
            if (registeredSerialNumbers[j] == _serialNo) {
                index = j;
                break;
            }
            j++;
        }

        for (uint256 i = index; i < registeredSerialNumbers.length - 1; i++) {
            registeredSerialNumbers[i] = registeredSerialNumbers[i + 1];
        }

        registeredSerialNumbers.pop();
    }

    function isLessThanAWeek(uint256 inputTime)
        public
        view
        returns (bool isExceed)
    {
        return ((block.timestamp - inputTime) / 60 / 60 / 24 <= 7);
    }
}

// Dummy time: 1671599994
