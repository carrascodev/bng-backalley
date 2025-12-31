angular.module('beamng.apps')
.directive('raceEditor', [function() {
  return {
    templateUrl: '/ui/modules/apps/RaceEditor/app.html',
    replace: true,
    restrict: 'EA',
    scope: {},
    controller: 'RaceEditorController'
  };
}])
.controller('RaceEditorController', ['$scope', '$timeout', function($scope, $timeout) {

  // ==================== STATE ====================
  // All state in objects to survive ng-if child scope

  $scope.editor = {
    active: false,
    currentTrackId: '',
    newTrackName: ''
  };

  $scope.trackList = [];

  $scope.trackData = {
    name: '',
    spawns: {
      player: null,
      adversaries: []
    },
    checkpoints: [],
    finish: null
  };

  $scope.ui = {
    showSpawns: true,
    showCheckpoints: true,
    showFinish: true,
    showSettings: false,
    showAIWaypoints: false
  };

  $scope.aiWaypoints = [];

  $scope.settings = {
    minBet: 1000,
    maxBet: 50000,
    difficulty: 2
  };

  // ==================== TRACK MANAGEMENT ====================

  $scope.loadTrackList = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.getTrackList()');
  };

  $scope.selectTrack = function() {
    var trackId = $scope.editor.currentTrackId;
    if (trackId) {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.loadTrack("' + trackId + '")');
    }
  };

  $scope.createNewTrack = function() {
    var name = $scope.editor.newTrackName;
    if (!name || name.trim() === '') {
      console.error('Race Editor: Track name is required');
      return;
    }
    name = name.trim();
    bngApi.engineLua('extensions.carTheft_raceEditorUI.createNewTrack("' + name.replace(/"/g, '\\"') + '")');
    $scope.editor.newTrackName = '';
  };

  $scope.saveTrack = function() {
    if ($scope.trackData && $scope.trackData.name) {
      var name = $scope.trackData.name.replace(/"/g, '\\"');
      bngApi.engineLua('extensions.carTheft_raceEditorUI.updateTrackName("' + name + '")');
    }
    bngApi.engineLua('extensions.carTheft_raceEditorUI.saveTrack()');
  };

  $scope.deleteTrack = function() {
    if (confirm('Delete track "' + $scope.trackData.name + '"?')) {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.deleteTrack("' + $scope.editor.currentTrackId + '")');
    }
  };

  $scope.updateTrackName = function() {
    var name = $scope.trackData.name || 'Unnamed';
    bngApi.engineLua('extensions.carTheft_raceEditorUI.updateTrackName("' + name.replace(/"/g, '\\"') + '")');
  };

  // ==================== SPAWN POSITIONS ====================

  $scope.setPlayerSpawn = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.setPlayerSpawn()');
  };

  $scope.clearPlayerSpawn = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.clearPlayerSpawn()');
  };

  $scope.addAdversarySpawn = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.addAdversarySpawn()');
  };

  $scope.removeAdversarySpawn = function(index) {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.removeAdversarySpawn(' + index + ')');
  };

  $scope.teleportToSpawn = function(type, index) {
    if (type === 'player') {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.teleportToPlayerSpawn()');
    } else {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.teleportToAdversarySpawn(' + index + ')');
    }
  };

  // ==================== CHECKPOINTS ====================

  $scope.addCheckpoint = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.addCheckpoint()');
  };

  $scope.removeCheckpoint = function(index) {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.removeCheckpoint(' + index + ')');
  };

  $scope.teleportToCheckpoint = function(index) {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.teleportToCheckpoint(' + index + ')');
  };

  $scope.setCheckpointWidth = function(index, width) {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.setCheckpointWidth(' + index + ', ' + width + ')');
  };

  // ==================== FINISH LINE ====================

  $scope.setFinishLine = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.setFinishLine()');
  };

  $scope.clearFinishLine = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.clearFinishLine()');
  };

  $scope.teleportToFinish = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.teleportToFinish()');
  };

  // ==================== SIMULATION ====================

  $scope.simulate = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.simulate()');
  };

  $scope.previewRoute = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.previewRoute()');
  };

  $scope.clearMarkers = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.clearMarkers()');
  };

  // ==================== AI WAYPOINTS ====================

  $scope.calculateAIWaypoints = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.calculateAIWaypoints()');
  };

  $scope.teleportToAIWaypoint = function(index) {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.teleportToAIWaypoint(' + index + ')');
  };

  // ==================== EDITING TOGGLE ====================

  $scope.toggleEditing = function() {
    $scope.editor.active = !$scope.editor.active;
    if ($scope.editor.active) {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.startEditing()');
      $scope.loadTrackList();
    } else {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.stopEditing()');
    }
  };

  // ==================== SETTINGS ====================

  $scope.toggleSettings = function() {
    $scope.ui.showSettings = !$scope.ui.showSettings;
  };

  $scope.updateSettings = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.updateSettings({' +
      'minBet = ' + $scope.settings.minBet + ', ' +
      'maxBet = ' + $scope.settings.maxBet + ', ' +
      'difficulty = ' + $scope.settings.difficulty +
    '})');
  };

  // ==================== FORMAT HELPERS ====================

  $scope.formatPos = function(pos) {
    if (!pos) return 'Not set';
    return pos.x.toFixed(1) + ', ' + pos.y.toFixed(1) + ', ' + pos.z.toFixed(1);
  };

  $scope.formatRot = function(rot) {
    if (!rot) return '';
    var yaw = Math.atan2(2 * (rot.w * rot.z + rot.x * rot.y), 1 - 2 * (rot.y * rot.y + rot.z * rot.z));
    return Math.round(yaw * 180 / Math.PI) + ' deg';
  };

  // ==================== EVENT LISTENERS ====================

  $scope.$on('RaceEditorTrackList', function(event, data) {
    $scope.$evalAsync(function() {
      $scope.trackList = data || [];
    });
  });

  $scope.$on('RaceEditorTrackLoaded', function(event, data) {
    $scope.$evalAsync(function() {
      if (data) {
        $scope.editor.currentTrackId = data.id || '';
        $scope.trackData.name = data.name || '';
        $scope.trackData.spawns = data.spawns || { player: null, adversaries: [] };
        $scope.trackData.checkpoints = data.checkpoints || [];
        $scope.trackData.finish = data.finish || null;
        $scope.settings = {
          minBet: data.minBet || 1000,
          maxBet: data.maxBet || 50000,
          difficulty: data.difficulty || 2
        };
      }
    });
  });

  $scope.$on('RaceEditorSpawnsUpdated', function(event, data) {
    $scope.$evalAsync(function() {
      if (data) {
        $scope.trackData.spawns = data;
      }
    });
  });

  $scope.$on('RaceEditorCheckpointsUpdated', function(event, data) {
    $scope.$evalAsync(function() {
      if (data) {
        $scope.trackData.checkpoints = data;
      }
    });
  });

  $scope.$on('RaceEditorFinishUpdated', function(event, data) {
    $scope.$evalAsync(function() {
      $scope.trackData.finish = data;
    });
  });

  $scope.$on('RaceEditorSaved', function(event, data) {
    $scope.$evalAsync(function() {
      if (data && data.success) {
        console.log('Race Editor: Track saved successfully');
        $scope.loadTrackList();
      }
    });
  });

  $scope.$on('RaceEditorNewTrack', function(event, data) {
    $scope.$evalAsync(function() {
      if (data) {
        $scope.editor.currentTrackId = data.id;
        $scope.trackData = {
          name: data.name,
          spawns: { player: null, adversaries: [] },
          checkpoints: [],
          finish: null
        };
        $scope.loadTrackList();
      }
    });
  });

  $scope.$on('RaceEditorDeleted', function(event, data) {
    $scope.$evalAsync(function() {
      $scope.editor.currentTrackId = '';
      $scope.trackData = {
        name: '',
        spawns: { player: null, adversaries: [] },
        checkpoints: [],
        finish: null
      };
      $scope.loadTrackList();
    });
  });

  $scope.$on('RaceEditorAIWaypoints', function(event, data) {
    $scope.$evalAsync(function() {
      $scope.aiWaypoints = data || [];
    });
  });

  $scope.$on('RaceEditorSimulating', function(event, data) {
    $scope.$evalAsync(function() {
      if (data && data.started) {
        console.log('Race Editor: Simulation started');
      }
    });
  });

  $scope.$on('RaceEditorError', function(event, data) {
    console.error('Race Editor error:', data.message);
  });

  // ==================== INITIALIZATION ====================

  bngApi.engineLua('extensions.load("carTheft_raceEditorUI")');

}]);
