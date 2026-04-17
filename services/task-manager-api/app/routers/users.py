from fastapi import APIRouter, Depends

from app.core.auth import CurrentUser, get_current_user
from app.schemas import CurrentUserOut

router = APIRouter(tags=["users"])


@router.get("/me", response_model=CurrentUserOut)
def get_me(current_user: CurrentUser = Depends(get_current_user)) -> CurrentUserOut:
    return CurrentUserOut(
        id=current_user.user_id,
        username=current_user.username,
        email=current_user.email,
        role=current_user.role,
    )
