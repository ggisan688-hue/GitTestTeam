package com.aicamp.changebook;

import jakarta.persistence.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@Entity
@Table(name = "change_book_user_spoiler_settings")
class UserSpoilerSetting {
  @Id @Column(name = "user_id") Long userId;
  @Column(nullable = false) boolean enabled = true;
}
interface UserSpoilerSettingRepository extends JpaRepository<UserSpoilerSetting,Long> {}
record SpoilerSettingRequest(@NotNull Boolean enabled) {}
record SpoilerSettingResponse(boolean enabled) {}

@org.springframework.stereotype.Service
class UserSpoilerSettingService {
  private final UserSpoilerSettingRepository settings;
  private final UserFeatureService users;
  UserSpoilerSettingService(UserSpoilerSettingRepository settings,UserFeatureService users) {
    this.settings=settings; this.users=users;
  }
  @Transactional(readOnly=true)
  SpoilerSettingResponse get(String username) {
    return new SpoilerSettingResponse(settings.findById(users.me(username).id)
        .map(s->s.enabled).orElse(true));
  }
  @Transactional
  SpoilerSettingResponse save(String username,SpoilerSettingRequest request) {
    Long id=users.me(username).id;
    UserSpoilerSetting value=settings.findById(id).orElseGet(()->{
      UserSpoilerSetting created=new UserSpoilerSetting();created.userId=id;return created;
    });
    value.enabled=request.enabled();
    return new SpoilerSettingResponse(settings.save(value).enabled);
  }
}
@RestController
@RequestMapping("/api/me/spoiler-setting")
class UserSpoilerSettingController {
  private final UserSpoilerSettingService service;
  UserSpoilerSettingController(UserSpoilerSettingService service){this.service=service;}
  @GetMapping SpoilerSettingResponse get(org.springframework.security.core.Authentication auth){return service.get(auth.getName());}
  @PatchMapping SpoilerSettingResponse save(org.springframework.security.core.Authentication auth,
      @Valid @RequestBody SpoilerSettingRequest request){return service.save(auth.getName(),request);}
}
