// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./Proposal.sol";
import "./MyToken.sol";


contract QuadraticVoting is Ownable{
    enum ProposalStatus {Pending, Approved, Rejected, Cancelled}

    struct Proposal {
        string title;
        string description;
        uint256 budget;
        uint256 proposalId;
        ProposalStatus status;
        SampleProposal executableProposal;
        address creator;
    }

    CompultenseToken public token; 
    uint256 public tokenPrice;
    uint256 public maxTokens;
    uint256 public totalBudget;
    bool public votingOpen;
    address[] public participants;
    mapping(address => bool) public isParticipant;
    Proposal[] public proposals;
    mapping(address => mapping(uint => uint)) public votes;

    constructor(uint256 _tokenPrice, uint256 _maxTokens) {
        token = new CompultenseToken();
        votingOpen = false;
        tokenPrice = _tokenPrice;
        maxTokens = _maxTokens;
        transferOwnership(msg.sender);
    }

    modifier onlyParticipant() {
        require(isParticipant[msg.sender], "Not a participant");
        _;
    }

    modifier onlyOpen(){
        require(votingOpen == true, "Voting must be open");
        _;
    }

    modifier onlyClosed(){
        require(votingOpen != true, "Voting Closed");
        _;
    }

    function addParticipant(address _participant) external payable {
        require(!isParticipant[_participant], "Already a participant");
        require(msg.value > 0, "Must transfer Ether to buy tokens");

        uint256 tokensToMint = msg.value / tokenPrice;
        require(tokensToMint >= 1, "Insufficient Ether to buy at least one token");

        participants.push(_participant);
        isParticipant[_participant] = true;

        token.mint(_participant, tokensToMint);

    }

    function removeParticipant(address _participant) external onlyOwner onlyParticipant{
        address temp;
        for (uint i = 0; i < participants.length; i++) {
            if (participants[i] == _participant) {
                temp = participants[i];
                participants[i] = participants[participants.length - 1];
                participants[participants.length - 1] = temp;
                participants.pop();
                isParticipant[_participant] = false;
                break;
            }
        }
    }



    function addProposal(string memory _title, string memory _description, uint256 _budget, SampleProposal _executableProposal) external onlyParticipant onlyOpen returns (uint proposalId) {
        proposalId = proposals.length;
        Proposal memory newProposal = Proposal(_title, _description, _budget, proposalId, ProposalStatus.Pending, _executableProposal, msg.sender);
        proposals.push(newProposal);
        return proposalId;
    }

    function cancelProposal(uint _proposalId) external onlyParticipant onlyOpen {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.creator == msg.sender, "Not the proposal creator");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending or already approved");

        proposal.status = ProposalStatus.Cancelled;

        for (uint i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint numVotes = votes[participant][_proposalId];

            if (numVotes > 0) {
                uint256 refund = (numVotes * (numVotes + 1) * (2 * numVotes + 1)) / 6; //the sum of first n squares
                token.transfer(participant, refund); 
                votes[participant][_proposalId] = 0;
            }
        }
    }

    function buyTokens() external payable onlyParticipant {
        uint256 tokenAmount = msg.value / tokenPrice;
        token.mint(msg.sender, tokenAmount);
    }   

    function sellTokens(uint256 _amount) external onlyParticipant {
        token.burn(msg.sender, _amount);
    }

    function getERC20() external view returns (ERC20) {
        return token;
    }

    function openVoting() external payable onlyOwner {
        require(!votingOpen, "Voting already open");

        totalBudget = msg.value;
        votingOpen = true;
    }

    function vote(uint _proposalId, uint _numVotes) external onlyParticipant {
        require(votingOpen, "Voting not open");
        require(proposals[_proposalId].status == ProposalStatus.Pending, "Proposal not pending");
        
        uint256 cost = (_numVotes * (_numVotes + 1) * (2 * _numVotes + 1)) / 6;
        require(token.balanceOf(msg.sender) >= cost, "Insufficient tokens");

        token.transferFrom(msg.sender, address(this), cost);
        votes[msg.sender][_proposalId] += _numVotes;
    }

    function stake(uint _proposalId, uint _numVotes) external onlyParticipant onlyOpen {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");

        uint256 requiredTokens = (_numVotes * (_numVotes + 1) * (2 * _numVotes + 1)) / 6;
        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= requiredTokens, "Tokens not approved");
        require(token.balanceOf(msg.sender) >= requiredTokens, "Insufficient tokens");

        token.transferFrom(msg.sender, address(this), requiredTokens);
        votes[msg.sender][_proposalId] += _numVotes;
    }

    function withdrawFromProposal(uint _proposalId) external onlyParticipant {
        require(proposals[_proposalId].status == ProposalStatus.Pending, "Proposal not pending");
        uint numVotes = votes[msg.sender][_proposalId];
        require(numVotes > 0, "No votes to withdraw");
        
        uint256 cost = (numVotes * (numVotes + 1) * (2 * numVotes + 1)) / 6;
        token.transfer(msg.sender, cost);
        votes[msg.sender][_proposalId] = 0;
    }

    function getProposalInfo(uint _proposalId) external view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    function getPendingProposals() external view onlyOpen returns (uint[] memory) {

        uint pendingCount = 0;
        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].status == ProposalStatus.Pending) {
                pendingCount++;
            }
        }

        uint[] memory pendingProposals = new uint[](pendingCount);
        uint index = 0;
        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].status == ProposalStatus.Pending) {
                pendingProposals[index] = i;
                index++;
            }
        }

        return pendingProposals;
    }

    function getSignalingProposals() external view onlyOpen returns (uint[] memory) {

        uint signalingCount = 0;
        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].budget == 0) {
                signalingCount++;
            }
        }

        uint[] memory signalingProposals = new uint[](signalingCount);
        uint index = 0;
        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].budget == 0) {
                signalingProposals[index] = i;
                index++;
            }
        }

        return signalingProposals;
    }

    function getApprovedProposals() external view onlyOpen returns (uint[] memory) {

        uint approvedCount = 0;
        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].status == ProposalStatus.Approved) {
                approvedCount++;
            }
        }

        uint[] memory approvedProposals = new uint[](approvedCount);
        uint index = 0;
        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].status == ProposalStatus.Approved) {
                approvedProposals[index] = i;
                index++;
            }
        }

        return approvedProposals;
    }

    function _checkAndExecuteProposal(uint _proposalId) private {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");

        uint256 totalVotes = 0;
        uint256 totalTokens = 0;
        for (uint i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint numVotes = votes[participant][_proposalId];
            totalVotes += numVotes;
            totalTokens += (numVotes * (numVotes + 1) * (2 * numVotes + 1)) / 6;
        }

        if (totalVotes * totalVotes >= proposal.budget && proposal.budget != 0) {
            proposal.status = ProposalStatus.Approved;
            token.transfer(address(proposal.executableProposal), proposal.budget);

            try proposal.executableProposal.executeProposal{gas: 100000}(_proposalId, totalVotes, totalTokens) {
            } catch {
                proposal.status = ProposalStatus.Rejected;
                token.transfer(owner(), proposal.budget);
            }

            for (uint i = 0; i < participants.length; i++) {
                address participant = participants[i];
                uint numVotes = votes[participant][_proposalId];
                if (numVotes > 0) {
                    votes[participant][_proposalId] = 0;
                }
            }
        } else {
            proposal.status = ProposalStatus.Rejected;
        }
    }

    function closeVoting() external onlyOwner onlyOpen {
        require(votingOpen, "Voting not open");
        votingOpen = false;

        for (uint i = 0; i < proposals.length; i++) {
            Proposal storage proposal = proposals[i];
            if (proposal.status == ProposalStatus.Pending) {
                _checkAndExecuteProposal(i);
            }

            if (proposal.status == ProposalStatus.Rejected) {
                for (uint j = 0; j < participants.length; j++) {
                    address participant = participants[j];
                    uint numVotes = votes[participant][i];
                    if (numVotes > 0) {
                        uint256 returnedTokens = (numVotes * (numVotes + 1) * (2 * numVotes + 1)) / 6;
                        token.transfer(participant, returnedTokens);
                    }
                }
            }

            if (proposal.status == ProposalStatus.Approved && proposal.budget == 0) {
                for (uint j = 0; j < participants.length; j++) {
                    address participant = participants[j];
                    uint numVotes = votes[participant][i];
                    if (numVotes > 0) {
                        uint256 returnedTokens = (numVotes * (numVotes + 1) * (2 * numVotes + 1)) / 6;
                        token.transfer(participant, returnedTokens);
                    }
                }
            }
        }

        uint256 remainingBudget = token.balanceOf(address(this));
        if (remainingBudget > 0) {
            token.transfer(owner(), remainingBudget);
        }
    }


}