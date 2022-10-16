// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Voting contract is a simple voting system.
 * It allows the owner to registered voters.
 * Registred voters can submit proposals during the proposal registration period
 * and can vote for a proposition during the voting session.
 *
 * Vote is not secret for registered voters.
 * Each registered voter can see each other vote at the end of the process.
 * Registered Proposal which has the more votes will win.
 */
contract Voting is Ownable {
    mapping(address => Voter) private _votersWhitelist;
    WorkflowStatus private _workflowStatus = WorkflowStatus.RegisteringVoters; // set default status to RegisteringVoters
    Proposal[] private _registeredProposals;
    uint private _winningProposalId;

    enum WorkflowStatus {
        RegisteringVoters, // registering voters period
        ProposalsRegistrationStarted, // registering proposals period
        ProposalsRegistrationEnded, // end of registering proposals
        VotingSessionStarted, // voting session period
        VotingSessionEnded, // end of voting session
        VotesTallied // votes are tallied and results could be announced
    }

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }
    struct Proposal {
        string description;
        uint voteCount;
    }

    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(
        WorkflowStatus previousStatus,
        WorkflowStatus newStatus
    );
    event ProposalRegistered(uint proposalId);
    event Voted(address voter, uint proposalId);

    modifier onlyVoters() {
        require(
            _votersWhitelist[msg.sender].isRegistered,
            "You are not in the voter list!"
        );
        _;
    }

    modifier requiresWorkflowStatus(
        WorkflowStatus _requiredWorkflowStatus,
        string memory _errorMessage
    ) {
        require(_workflowStatus == _requiredWorkflowStatus, _errorMessage);
        _;
    }

    /**
     * @dev Register a new voter in the whitelist. Only owner can run this method.
     * The workflowStatus has to be in RegisteringVoters state.
     * @param _newVoterAddress the voter adress to register.
     **/
    function registerVoter(address _newVoterAddress)
        external
        onlyOwner
        requiresWorkflowStatus(
            WorkflowStatus.RegisteringVoters,
            "Voters registration is closed!"
        )
    {
        require(
            !_votersWhitelist[_newVoterAddress].isRegistered,
            "This voter is already registered!"
        );
        _votersWhitelist[_newVoterAddress].isRegistered = true;
        emit VoterRegistered(_newVoterAddress);
    }

    /**
     * @dev Use this method to change the workflow status. Only owner can run this method.
     * @param _newWorkflowStatus the status to update to. See WorkflowStatus enum for more details.
     **/
    function updateWorkflowStatus(WorkflowStatus _newWorkflowStatus)
        external
        onlyOwner
    {
        WorkflowStatus oldWorkflowStatus = _workflowStatus;
        _workflowStatus = _newWorkflowStatus;
        emit WorkflowStatusChange(oldWorkflowStatus, _newWorkflowStatus);
    }

    /**
     * @dev Tally votes. Only owner can run this method. Id of the winning proposal is stored on winningProposalId variable.
     * The workflowStatus has to be in WorkflowStatus.VotingSessionEnded state.
     */
    function tallyVotes()
        external
        onlyOwner
        requiresWorkflowStatus(
            WorkflowStatus.VotingSessionEnded,
            "Voting session is not ended yet!"
        )
    {
        uint maxVotes;
        for (uint i = 0; i < _registeredProposals.length; i++) {
            if (_registeredProposals[i].voteCount > maxVotes) {
                maxVotes = _registeredProposals[i].voteCount;
                _winningProposalId = i;
            }
        }
    }

    /**
     * @dev Vote for a proposal. Only registered voters can vote. A voter can vote only during the voting session, and only once.
     * @param _proposalId id of the proposal ( = index of the proposal in the proposals array)
     * The workflowStatus has to be in RegisteVotingSessionStarted state.
     */
    function vote(uint _proposalId)
        external
        onlyVoters
        requiresWorkflowStatus(
            WorkflowStatus.VotingSessionStarted,
            "Voting session is not started yet!"
        )
    {
        require(!_votersWhitelist[msg.sender].hasVoted, "You already voted!");

        _votersWhitelist[msg.sender].votedProposalId = _proposalId;
        _registeredProposals[_proposalId].voteCount++;
        _votersWhitelist[msg.sender].hasVoted = true;

        emit Voted(msg.sender, _proposalId);
    }

    /**
     * @dev Register a proposal. Only registered voters can register a proposal.
     * The workflowStatus has to be in ProposalsRegistrationStarted state.
     * @param _proposalDescription description of the proposal to add.
     */
    function registerProposal(string calldata _proposalDescription)
        external
        onlyVoters
        requiresWorkflowStatus(
            WorkflowStatus.ProposalsRegistrationStarted,
            "Proposals registration is closed!"
        )
    {
        if (_isProposalAlreadyRegistered(_proposalDescription)) {
            revert("This proposal is already registered!");
        }
        _registeredProposals.push(Proposal(_proposalDescription, 0));
        emit ProposalRegistered(_registeredProposals.length - 1);
    }

    /**
     * @dev Get the registered proposals. Only registered voters can see these.
     * @return an array of Proposal.
     */
    function getRegisteredProposals()
        external
        view
        onlyVoters
        returns (Proposal[] memory)
    {
        return _registeredProposals;
    }

    /**
     * @dev Get the voted proposal id a voter voted for. This can be seen by any registered voter.
     * The workflow status has to be in VotesTallied state.
     * @param _voterAddress the voter's address.
     * @return the voted proposal id.
     */
    function getVoterVotedProposalId(address _voterAddress)
        external
        view
        onlyVoters
        requiresWorkflowStatus(
            WorkflowStatus.VotesTallied,
            "Votes are not tallied yet!"
        )
        returns (uint)
    {
        return _votersWhitelist[_voterAddress].votedProposalId;
    }

    /**
     * @dev Get winning proposal id. This can be seen by registered voters only.
     * The workflow status has to be in VotesTallied state.
     * @return the winning proposal id.
     */
    function getWinningProposalId()
        external
        view
        onlyVoters
        requiresWorkflowStatus(
            WorkflowStatus.VotesTallied,
            "Votes are not tallied yet!"
        )
        returns (uint)
    {
        return _winningProposalId;
    }

    /**
     * @dev private method to check if the proposal is alread registered.
     * @param _proposalDescription the proposal description
     * @return true if the proposal already exists, false otherwise
     */
    function _isProposalAlreadyRegistered(string calldata _proposalDescription)
        private
        view
        returns (bool)
    {
        for (uint i = 0; i < _registeredProposals.length; i++) {
            if (
                keccak256(bytes(_registeredProposals[i].description)) ==
                keccak256(bytes(_proposalDescription))
            ) {
                return true;
            }
        }
        return false;
    }
}
